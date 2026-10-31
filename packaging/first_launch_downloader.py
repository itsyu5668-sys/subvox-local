#!/usr/bin/env python3
"""Subvox Local — first-launch model downloader.

Downloads the model weights on first launch, into:
    ~/Library/Application Support/Subvox Local/models/

Stdlib only (urllib) — runs with the macOS system python3, no venv needed,
so the Swift app can run it before the Python backend exists.

UNTESTED ON INTEL MAC: written and syntax-checked on a Linux VM.
Run it once by hand on the Intel Mac before shipping:
    python3 packaging/first_launch_downloader.py --models-dir /tmp/sv-models-test

What it does:
  * Core models only by default (~1.62 GB total for usable dictation):
    the VSR core set (~1.22 GB: Auto-AVSR visual-only, subword LM,
    SentencePiece tokenizer, MediaPipe FaceLandmarker) PLUS the
    Qwen3-0.6B Q4_K_M GGUF cleanup model (~396.7 MB, unsloth,
    SHA-256 verified). Without the GGUF file, cleanup falls back to
    offline rules only — so it is core, not optional.
  * Resumable: interrupted downloads continue from the .part file
    (HTTP Range). Re-running skips files already present with a
    matching SHA-256.
  * Verifies SHA-256 after every file (hashes below were computed from
    the actual downloaded files in this repo's models/ on 2026-10-31).
    A bad hash deletes the file and retries once, then fails loudly.
  * Progress: prints PROGRESS lines to stdout AND writes a JSON file
    the Swift UI reads (default:
    ~/Library/Application Support/Subvox Local/download-progress.json).
    Fields: current_file, downloaded_bytes, total_bytes, percent,
    overall_downloaded_bytes, overall_total_bytes, overall_percent,
    bytes_per_sec, eta_seconds, overall_eta_seconds,
    status (downloading | paused | cancelled | done | error),
    models_done, models_total.
    bytes_per_sec is an exponentially-weighted moving average of the
    download rate; eta_seconds is (remaining bytes / bytes_per_sec)
    and is 0 / null until enough data has been seen to estimate it.
    The Swift UI (DownloadProgressMonitor) polls this file once a
    second — the downloader never talks to the UI directly.
  * Pause / cancel: create the pause file or cancel file named in
    --pause-file / --cancel-file (defaults live next to the progress
    file). The downloader checks them between chunks and stops cleanly;
    the .part file stays, so the next run resumes.

What it does NOT download (on purpose):
  * Qwen3 MLX files (0.6B / 1.7B, ~1.3 GB). MLX does not run on Intel
    Macs, so those weights are dead weight on this machine. They are
    listed in the manifest with group "qwen-mlx" and skipped unless
    --include-qwen-mlx is passed (only useful on Apple Silicon).
  * AV whisper model (1.8 GB) and AV-HuBERT backup (1.9 GB) are
    optional on-demand downloads only: --include-av / --include-avhubert.
    Shipping them by default would take first-run download from
    ~1.62 GB to ~5.33 GB for features most users never touch
    (whisper mode, backup encoder). See docs/SEAMLESS_FLOW.md §3
    for the size math.

All URLs below are copied verbatim from scripts/download-models.sh.
No URL was invented.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import signal
import sys
import time
import urllib.error
import urllib.request

HF = "https://huggingface.co"

# dest is relative to the models dir. sha256 is the full hash of the file
# as downloaded in this repo (see MODELS.md for the first-16-hex prefixes).
# size_mb is approximate, from MODELS.md.
MANIFEST = [
    # ---- core (required) ~1.22 GB ----
    {"name": "Auto-AVSR config", "group": "core",
     "url": f"{HF}/Amanvir/LRS3_V_WER19.1/resolve/main/model.json",
     "dest": "vsr/model.json",
     "sha256": "e062e8c58579f54cb51087e639e674781189809905db4162efe0fe1325356d4f",
     "size_mb": 0.01},
    {"name": "Auto-AVSR visual-only weights (LRS3 19.1% WER)", "group": "core",
     "url": f"{HF}/Amanvir/LRS3_V_WER19.1/resolve/main/model.pth",
     "dest": "vsr/model.pth",
     "sha256": "e740cef369abeabd0ba2c18e37a0661342e1d94d432d6caa77755a11821d8fe3",
     "size_mb": 1001.9},
    {"name": "Subword LM config", "group": "core",
     "url": f"{HF}/Amanvir/lm_en_subword/resolve/main/model.json",
     "dest": "lm/model.json",
     "sha256": "6e2d2004e4066af3e5a3d74c53b0d648fd53904da07178671d1cbe28a206d548",
     "size_mb": 0.01},
    {"name": "Subword LM weights", "group": "core",
     "url": f"{HF}/Amanvir/lm_en_subword/resolve/main/model.pth",
     "dest": "lm/model.pth",
     "sha256": "c75aa39020dec98f432c8689b145d3f4cc407d4daa90a0c64202386c34f83c18",
     "size_mb": 215.1},
    {"name": "SentencePiece unigram5000 tokenizer", "group": "core",
     "url": "https://github.com/mpc001/auto_avsr/raw/main/spm/unigram/unigram5000.model",
     "dest": "lm/unigram5000.model",
     "sha256": "2c1d648ccf5fdce6612ecbea2ffbd1cab5aabc90458781186175c3911c4bdb1e",
     "size_mb": 0.3},
    {"name": "MediaPipe FaceLandmarker", "group": "core",
     "url": "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task",
     "dest": "face_landmarker.task",
     "sha256": "64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff",
     "size_mb": 3.8},
    # ---- optional: whisper mode (AV) ~1.78 GB ----
    {"name": "AV model config (whisper mode)", "group": "av",
     "url": f"{HF}/nguyenvulebinh/auto_avsr_av_trlrwlrs2lrs3vox2avsp_base/resolve/main/config.json",
     "dest": "av/config.json",
     "sha256": "555aa10a41405f9f121808fa7161b4c47a5c2a0b4d2b276b4a29579c71fbc959",
     "size_mb": 0.01},
    {"name": "AV model weights (whisper mode)", "group": "av",
     "url": f"{HF}/nguyenvulebinh/auto_avsr_av_trlrwlrs2lrs3vox2avsp_base/resolve/main/model.safetensors",
     "dest": "av/model.safetensors",
     "sha256": "1e013dbec3ba367a2c5da7d12a8e9d70c181512d39bea630a694a20cf17470cc",
     "size_mb": 1776.4},
    # ---- optional: AV-HuBERT backup ~1.93 GB ----
    {"name": "AV-HuBERT Large (backup VSR encoder only)", "group": "avhubert",
     "url": f"{HF}/vumichien/AV-HuBERT/resolve/main/model.pt",
     "dest": "avhubert/model.pt",
     "sha256": "84c83698c831b447cb75db0d14b72040c021c9a442ee1208d306b1091c00756d",
     "size_mb": 1928.1},
    # ---- Qwen3 MLX: skipped on Intel by default (MLX is Apple Silicon only) ----
    {"name": "Qwen3-0.6B MLX config", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-0.6B-4bit/resolve/main/config.json",
     "dest": "qwen3-0.6b-4bit-mlx/config.json",
     "sha256": "15d3ac26c043ae477273ed5802ee0f0b33bb14f18c9d3dd70910c02d906e3f1f",
     "size_mb": 0.01},
    {"name": "Qwen3-0.6B MLX weights", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-0.6B-4bit/resolve/main/model.safetensors",
     "dest": "qwen3-0.6b-4bit-mlx/model.safetensors",
     "sha256": "392e8d466d56100ada00eb82031fb854297fc9e389b7d303eba3af114e87bce2",
     "size_mb": 335.5},
    {"name": "Qwen3-0.6B MLX tokenizer", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-0.6B-4bit/resolve/main/tokenizer.json",
     "dest": "qwen3-0.6b-4bit-mlx/tokenizer.json",
     "sha256": "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4",
     "size_mb": 11.4},
    {"name": "Qwen3-0.6B MLX tokenizer config", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-0.6B-4bit/resolve/main/tokenizer_config.json",
     "dest": "qwen3-0.6b-4bit-mlx/tokenizer_config.json",
     "sha256": "253153d0738ceb4c668d2eff957714dd2bea0b56de772a9fdccd96cbf517e6a0",
     "size_mb": 0.01},
    {"name": "Qwen3-0.6B MLX vocab", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-0.6B-4bit/resolve/main/vocab.json",
     "dest": "qwen3-0.6b-4bit-mlx/vocab.json",
     "sha256": "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910",
     "size_mb": 2.8},
    {"name": "Qwen3-0.6B MLX merges", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-0.6B-4bit/resolve/main/merges.txt",
     "dest": "qwen3-0.6b-4bit-mlx/merges.txt",
     "sha256": "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5",
     "size_mb": 1.7},
    {"name": "Qwen3-0.6B MLX added tokens", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-0.6B-4bit/resolve/main/added_tokens.json",
     "dest": "qwen3-0.6b-4bit-mlx/added_tokens.json",
     "sha256": "c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680",
     "size_mb": 0.01},
    {"name": "Qwen3-0.6B MLX special tokens", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-0.6B-4bit/resolve/main/special_tokens_map.json",
     "dest": "qwen3-0.6b-4bit-mlx/special_tokens_map.json",
     "sha256": "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd",
     "size_mb": 0.01},
    {"name": "Qwen3-1.7B MLX config", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-1.7B-4bit/resolve/main/config.json",
     "dest": "qwen3-1.7b-4bit-mlx/config.json",
     "sha256": "507a6701220524eb8b283425bf0856a9ae4f21f4052e563896ddd668994b1dc7",
     "size_mb": 0.01},
    {"name": "Qwen3-1.7B MLX weights", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-1.7B-4bit/resolve/main/model.safetensors",
     "dest": "qwen3-1.7b-4bit-mlx/model.safetensors",
     "sha256": "0e86d9677e519323849eac1bc272caae88567a481ff188c431f70be543d9995f",
     "size_mb": 968.1},
    {"name": "Qwen3-1.7B MLX tokenizer", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-1.7B-4bit/resolve/main/tokenizer.json",
     "dest": "qwen3-1.7b-4bit-mlx/tokenizer.json",
     "sha256": "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4",
     "size_mb": 11.4},
    {"name": "Qwen3-1.7B MLX tokenizer config", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-1.7B-4bit/resolve/main/tokenizer_config.json",
     "dest": "qwen3-1.7b-4bit-mlx/tokenizer_config.json",
     "sha256": "253153d0738ceb4c668d2eff957714dd2bea0b56de772a9fdccd96cbf517e6a0",
     "size_mb": 0.01},
    {"name": "Qwen3-1.7B MLX vocab", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-1.7B-4bit/resolve/main/vocab.json",
     "dest": "qwen3-1.7b-4bit-mlx/vocab.json",
     "sha256": "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910",
     "size_mb": 2.8},
    {"name": "Qwen3-1.7B MLX merges", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-1.7B-4bit/resolve/main/merges.txt",
     "dest": "qwen3-1.7b-4bit-mlx/merges.txt",
     "sha256": "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5",
     "size_mb": 1.7},
    {"name": "Qwen3-1.7B MLX added tokens", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-1.7B-4bit/resolve/main/added_tokens.json",
     "dest": "qwen3-1.7b-4bit-mlx/added_tokens.json",
     "sha256": "c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680",
     "size_mb": 0.01},
    {"name": "Qwen3-1.7B MLX special tokens", "group": "qwen-mlx",
     "url": f"{HF}/mlx-community/Qwen3-1.7B-4bit/resolve/main/special_tokens_map.json",
     "dest": "qwen3-1.7b-4bit-mlx/special_tokens_map.json",
     "sha256": "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd",
     "size_mb": 0.01},
    # ---- Qwen3 GGUF (Intel cleanup) — CORE, downloaded by default ----
    # Chosen 2026-10-31, verified in this repo (MODELS.md):
    # unsloth/Qwen3-0.6B-GGUF, file Qwen3-0.6B-Q4_K_M.gguf,
    # 396,705,472 bytes, sha256 ac2d9771... (full hash below).
    # NOTE the exact filename case: Qwen3-0.6B-Q4_K_M.gguf — the
    # cleanup code (src/subvox_local/paths.py QWEN_06B_GGUF) looks
    # for exactly this name. Do not lowercase it.
    {"name": "Qwen3-0.6B GGUF (llama.cpp, Intel cleanup)", "group": "qwen-gguf",
     "url": f"{HF}/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf",
     "dest": "qwen3-0.6b-gguf/Qwen3-0.6B-Q4_K_M.gguf",
     "sha256": "ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a",
     "size_mb": 396.7},
]

CHUNK = 1024 * 1024  # 1 MB chunks; pause/cancel checked between chunks


class Cancelled(Exception):
    pass


class Paused(Exception):
    pass


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(4 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


class Downloader:
    def __init__(self, models_dir: str, progress_file: str,
                 pause_file: str, cancel_file: str):
        self.models_dir = models_dir
        self.progress_file = progress_file
        self.pause_file = pause_file
        self.cancel_file = cancel_file
        self.overall_total = 0
        self.overall_done = 0
        self.models_done = 0
        self.models_total = 0
        self._cancelled = False
        self._error_message = ""
        # Download-rate tracking for ETA (see _write_progress):
        # EWMA of bytes/sec, updated once per progress write (1 Hz).
        self._rate_bps = 0.0
        self._last_write_time = 0.0
        self._last_overall_done = 0
        signal.signal(signal.SIGINT, self._on_sigint)
        try:
            signal.signal(signal.SIGTERM, self._on_sigint)
        except Exception:
            pass

    def _on_sigint(self, *_args):
        self._cancelled = True

    # -- progress ------------------------------------------------------
    def _write_progress(self, status: str, current: str = "",
                        downloaded: int = 0, total: int = 0,
                        error_message: str = "") -> None:
        if error_message:
            self._error_message = error_message
        overall_pct = (100.0 * self.overall_done / self.overall_total
                       if self.overall_total else 0.0)
        pct = 100.0 * downloaded / total if total else 0.0
        # Rate + ETA: EWMA over 1-second writes. First write has no
        # rate yet (rate 0 -> ETA null, not a fake number).
        now = time.time()
        if self._last_write_time:
            dt = max(now - self._last_write_time, 0.001)
            instant = (self.overall_done - self._last_overall_done) / dt
            alpha = 0.3
            self._rate_bps = (alpha * instant + (1 - alpha) * self._rate_bps
                              if self._rate_bps else instant)
        self._last_write_time = now
        self._last_overall_done = self.overall_done
        rate = self._rate_bps
        eta_file = (int((total - downloaded) / rate) if rate > 0 and total > downloaded
                    else None)
        eta_overall = (int((self.overall_total - self.overall_done) / rate)
                       if rate > 0 and self.overall_total > self.overall_done
                       else None)
        data = {
            "status": status,
            "current_file": current,
            "downloaded_bytes": downloaded,
            "total_bytes": total,
            "percent": round(pct, 1),
            "overall_downloaded_bytes": self.overall_done,
            "overall_total_bytes": self.overall_total,
            "overall_percent": round(overall_pct, 1),
            "bytes_per_sec": round(rate, 1),
            "eta_seconds": eta_file,
            "overall_eta_seconds": eta_overall,
            "models_done": self.models_done,
            "models_total": self.models_total,
            "updated": time.strftime("%Y-%m-%dT%H:%M:%S"),
            # Plain-English failure reason, shown in the app UI (not
            # only in the log). Empty unless status == "error".
            # The Swift monitor treats a progress file whose "updated"
            # timestamp is >60s old while status is "downloading" as
            # stalled — that is how a frozen download is detected.
            "error_message": self._error_message,
        }
        tmp = self.progress_file + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, self.progress_file)
        eta_txt = f" ETA {eta_overall}s" if eta_overall is not None else ""
        print(f"PROGRESS {current} {downloaded}/{total} ({pct:.1f}%) "
              f"overall {overall_pct:.1f}% {rate / 1e6:.1f} MB/s{eta_txt} [{status}]",
              flush=True)

    def _check_pause_cancel(self) -> None:
        if self._cancelled or os.path.exists(self.cancel_file):
            raise Cancelled("cancel requested")
        while os.path.exists(self.pause_file):
            print("PAUSED — remove the pause file to resume "
                  f"({self.pause_file})", flush=True)
            self._write_progress("paused")
            time.sleep(2)
            if self._cancelled or os.path.exists(self.cancel_file):
                raise Cancelled("cancel requested while paused")

    # -- one file ------------------------------------------------------
    def _download_one(self, entry: dict) -> bool:
        """Returns True if the file is present and verified afterwards."""
        dest = os.path.join(self.models_dir, entry["dest"])
        part = dest + ".part"
        os.makedirs(os.path.dirname(dest), exist_ok=True)

        if os.path.exists(dest) and entry.get("sha256"):
            if sha256_of(dest) == entry["sha256"]:
                print(f"✓ {entry['dest']} (already present, hash ok)")
                self.overall_done += int(entry["size_mb"] * 1024 * 1024)
                self.models_done += 1
                return True
            print(f"! {entry['dest']} present but hash mismatch — re-downloading")
            os.remove(dest)

        url = entry["url"]
        resume_from = os.path.getsize(part) if os.path.exists(part) else 0
        if resume_from:
            print(f"↻ resuming {entry['dest']} from {resume_from / 1e6:.1f} MB")

        req = urllib.request.Request(url)
        if resume_from:
            req.add_header("Range", f"bytes={resume_from}-")
        try:
            resp = urllib.request.urlopen(req, timeout=60)
        except urllib.error.HTTPError as e:
            if e.code == 416:  # Range not satisfiable: .part is complete/stale
                os.remove(part)
                return self._download_one(entry)
            raise
        # Server ignored Range and sent the whole file: restart cleanly.
        if resume_from and resp.status == 200:
            print("  (server ignored Range, restarting file from 0)")
            resume_from = 0
            if os.path.exists(part):
                os.remove(part)
        total = int(resp.headers.get("Content-Length", "0") or 0) + resume_from
        if total == 0 and entry.get("size_mb"):
            total = int(entry["size_mb"] * 1024 * 1024)  # estimate only

        mode = "ab" if resume_from else "wb"
        downloaded = resume_from
        last_report = 0.0
        with open(part, mode) as f:
            while True:
                self._check_pause_cancel()
                chunk = resp.read(CHUNK)
                if not chunk:
                    break
                f.write(chunk)
                downloaded += len(chunk)
                self.overall_done += len(chunk)
                now = time.time()
                if now - last_report >= 1.0:
                    self._write_progress("downloading", entry["dest"],
                                         downloaded, total)
                    last_report = now
        self._write_progress("downloading", entry["dest"], downloaded, total)

        if entry.get("sha256"):
            actual = sha256_of(part)
            if actual != entry["sha256"]:
                print(f"✗ SHA mismatch for {entry['dest']}\n"
                      f"  expected {entry['sha256']}\n  got      {actual}")
                os.remove(part)
                return False
        os.replace(part, dest)
        self.models_done += 1
        print(f"✓ {entry['dest']} ({downloaded / 1e6:.1f} MB, hash ok)")
        return True

    # -- run -----------------------------------------------------------
    def run(self, entries: list[dict]) -> int:
        self.models_total = len(entries)
        self.overall_total = sum(int(e["size_mb"] * 1024 * 1024)
                                 for e in entries if e.get("size_mb"))
        # Count already-present bytes toward the overall total.
        for e in entries:
            dest = os.path.join(self.models_dir, e["dest"])
            if os.path.exists(dest) and e.get("sha256"):
                try:
                    if sha256_of(dest) == e["sha256"]:
                        self.overall_done += int(e["size_mb"] * 1024 * 1024)
                except OSError:
                    pass
        print(f"Downloading {len(entries)} model file(s), "
              f"~{self.overall_total / 1e9:.2f} GB total, into {self.models_dir}")
        self._write_progress("downloading")
        try:
            for entry in entries:
                if entry.get("url") is None:
                    print(f"⚠ SKIP {entry['name']}: no URL yet (see header comment). "
                          "Intel cleanup will use offline rules until a GGUF "
                          "file is chosen and the cleanup branch lands.")
                    self.models_total -= 1
                    continue
                # Network errors (wifi drop, Hugging Face timeout, HTTP
                # error) used to crash this process with a traceback and
                # leave the progress file stuck on "downloading" forever,
                # so the app showed a frozen percent and no error.
                # Now they are caught, written to the progress file as
                # status "error" with a plain-English reason, retried
                # once after 5s, and only then fail. Completed files
                # are kept and verified files are skipped on re-run.
                ok = False
                last_error = ""
                for attempt in (1, 2):
                    try:
                        ok = self._download_one(entry)
                    except Exception as e:  # URLError, HTTPError, timeout, OSError
                        last_error = f"{type(e).__name__}: {e}"
                        print(f"Download error for {entry['dest']} "
                              f"(attempt {attempt}): {last_error}")
                        ok = False
                    if ok:
                        break
                    if attempt == 1:
                        print("Waiting 5s, then retrying once…")
                        time.sleep(5)
                if not ok:
                    reason = (last_error or
                              f"could not download {entry['dest']} "
                              "(hash check failed twice)")
                    self._write_progress("error", entry["dest"],
                                         error_message=reason)
                    print(f"FAILED: {entry['dest']} — {reason}. Check "
                          "your internet, then re-open the app; completed "
                          "files are kept and verified files are skipped.")
                    return 1
        except (Cancelled, KeyboardInterrupt):
            self._write_progress("cancelled")
            print("Cancelled. Partial downloads are kept as .part files — "
                  "re-run to resume.")
            return 2
        except Paused:
            self._write_progress("paused")
            return 3
        except Exception as e:  # never die with a stale "downloading" file
            reason = f"{type(e).__name__}: {e}"
            self._write_progress("error", error_message=reason)
            print(f"FAILED unexpectedly: {reason}. Re-open the app to "
                  "resume; completed files are kept.")
            return 1
        self._write_progress("done")
        print(f"Done: {self.models_done}/{self.models_total} files verified "
              f"in {self.models_dir}")
        return 0


def select_entries(args) -> list[dict]:
    # Core by default: VSR core set + GGUF cleanup (~1.62 GB total).
    # The GGUF file is core, not optional — without it cleanup falls
    # back to offline rules. --include-qwen-gguf is kept as a no-op
    # flag for scripts that already pass it.
    groups = {"core", "qwen-gguf"}
    if args.include_av:
        groups.add("av")
    if args.include_avhubert:
        groups.add("avhubert")
    if args.include_qwen_mlx:
        groups.add("qwen-mlx")
    else:
        print("NOTE: Qwen3 MLX files skipped (MLX does not run on Intel Macs).")
    return [e for e in MANIFEST if e["group"] in groups]


def main(argv=None) -> int:
    home = os.path.expanduser("~/Library/Application Support/Subvox Local")
    p = argparse.ArgumentParser(
        description="Subvox Local first-launch model downloader (Intel Mac).")
    p.add_argument("--models-dir", default=os.path.join(home, "models"),
                   help="where model files go")
    p.add_argument("--progress-file", default=os.path.join(home, "download-progress.json"))
    p.add_argument("--pause-file", default=os.path.join(home, "download.pause"))
    p.add_argument("--cancel-file", default=os.path.join(home, "download.cancel"))
    p.add_argument("--include-av", action="store_true",
                   help="also download the 1.8 GB AV whisper model")
    p.add_argument("--include-avhubert", action="store_true",
                   help="also download the 1.9 GB AV-HuBERT backup")
    p.add_argument("--include-qwen-mlx", action="store_true",
                   help="also download MLX Qwen files (useless on Intel, "
                        "only for Apple Silicon)")
    p.add_argument("--include-qwen-gguf", action="store_true",
                   help="no-op: the GGUF cleanup model is core and is "
                        "downloaded by default. Kept so older scripts "
                        "that pass the flag keep working.")
    p.add_argument("--list", action="store_true",
                   help="print the manifest and exit")
    p.add_argument("--verify-only", action="store_true",
                   help="check hashes of already-downloaded files, download nothing")
    args = p.parse_args(argv)

    if args.list:
        for e in MANIFEST:
            print(f"{e['group']:10s} {e['dest']:45s} "
                  f"{(e['size_mb'] or 0):>8} MB  {e['url'] or 'NO URL YET'}")
        return 0

    entries = select_entries(args)
    os.makedirs(args.models_dir, exist_ok=True)
    os.makedirs(os.path.dirname(args.progress_file), exist_ok=True)

    if args.verify_only:
        missing, bad = [], []
        for e in entries:
            dest = os.path.join(args.models_dir, e["dest"])
            if not os.path.exists(dest):
                missing.append(e["dest"])
            elif e.get("sha256") and sha256_of(dest) != e["sha256"]:
                bad.append(e["dest"])
        print(f"present+ok: {len(entries) - len(missing) - len(bad)}  "
              f"missing: {missing}  bad-hash: {bad}")
        return 0 if not missing and not bad else 1

    dl = Downloader(args.models_dir, args.progress_file,
                    args.pause_file, args.cancel_file)
    return dl.run(entries)


if __name__ == "__main__":
    raise SystemExit(main())
