# Subvox Local — silent lip-reading dictation, 100% on-device

**Hold a key, silently mouth words at your webcam, text appears at your cursor in any app.**
No microphone, no sound, no cloud. Camera + Auto-AVSR + offline Qwen cleanup, all local.

This replaces the original Subvox idea (AirPods head-motion, DTW, 5 words only —
see `/tmp/subvox`, kept as reference) with the Lipflow blueprint
(amywork777/lipflow, Oct 5 2026, MIT code): webcam → MediaPipe landmarks →
96×96 mouth crops at 25 fps → Auto-AVSR (19.1% WER on LRS3) → top-3 beam +
offline Qwen3-0.6B cleanup → paste at cursor.

## What is different from Lipflow

- **Fast setup:** 10 phonetically balanced sentences (not 24), LoRA quick
  adapt (rank 8, ~0.6M params, max 300 steps, base frozen) instead of a
  full front-end fine-tune. Stage 1 is 6 sentences, ~2 minutes, usable
  immediately; stage 2 finishes in the background. See
  `docs/FAST_SETUP_PLAN.md` for the full plan and why quality should hold.
- **No cloud anywhere:** no Anthropic, no OpenAI, no Codex. Cleanup is
  MLX Qwen3 on-device (Apple Silicon) or GGUF Qwen3 via llama.cpp
  (Intel — landed 2026-10-31, see docs/INTEL_MAC.md), or offline
  rules if neither is available.
- **Honest status:** everything Mac-only (hotkey, paste, menu bar) is
  marked UNTESTED ON INTEL MAC in this build — it was built on a Linux
  VM, which cannot build a .app or .dmg (no Xcode, no macOS toolchain).
  See "What works / what is untested" below.

## Quick start (on Francis's Mac — INTEL Core i5, macOS 14+, camera)

> **Francis's Mac is Intel Core i5, not Apple Silicon.** MLX does not
> run on Intel. The backend is PyTorch CPU + GGUF Qwen via llama.cpp.
> The old Apple Silicon setup is kept as `setup_apple_silicon.sh` for
> reference only.

**One-click install (the .app):** see `packaging/README.md`. On the Mac:

```sh
./packaging/build_app.sh      # builds Subvox Local.app (~10–30 min first time)
./packaging/build_dmg.sh      # builds Subvox Local.dmg
# Open the .dmg, drag Subvox Local.app to Applications, double-click.
# First launch downloads ~1.22 GB of models (resumable, SHA-verified).
```

**Dev / CLI setup (no .app):**

```sh
./setup_macos.sh              # dispatches to setup_intel_macos.sh on Intel
# 1. Grant Camera, Input Monitoring, Accessibility when asked
# 2. Fast setup (CPU LoRA — SLOWER than the old ~2 min Apple Silicon target, time it):
uv run python -m subvox_local setup-fast
# 3. Personal LM (optional but the biggest accuracy win — import your own text first):
uv run python -m subvox_local import-text my-writing.txt
uv run python -m subvox_local train-lm
# 4. Dictate: hold Right Option anywhere, mouth words, release.
#    Or test a file:  uv run python -m subvox_local file talk.mp4
```

Full Mac test steps: `docs/FAST_SETUP_PLAN.md` (its Apple Silicon
timings do NOT apply on Intel — re-measure everything).

## Project layout

```
subvox-local/
  README.md  LICENSES.md  MODELS.md
  setup_macos.sh            # dispatcher: Intel -> setup_intel_macos.sh, arm64 -> setup_apple_silicon.sh
  setup_intel_macos.sh      # Intel Mac setup (uv, CPU deps, core models, doctor)
  setup_apple_silicon.sh    # Apple Silicon setup (kept for reference; MLX only)
  packaging/                # one-click install: build_app.sh, build_dmg.sh,
                            # PyInstaller.spec, first_launch_downloader.py,
                            # launcher.sh, Info.plist, entitlements, README.md
  pyproject.toml
  scripts/download-models.sh  # all model downloads, resumable
  models/                   # downloaded weights (see MODELS.md)
    vsr/  lm/  av/  qwen3-0.6b-4bit-mlx/  qwen3-1.7b-4bit-mlx/  avhubert/
    face_landmarker.task
  src/subvox_local/         # new app code
    paths.py  visemes.py  sentences.py  capture.py  face.py  vsr.py
    adapt.py  cleanup.py  lm_train.py  corrections.py  dictation.py
    paste.py  app.py  __main__.py
  swift/SubvoxLocalApp.swift  # menu-bar wrapper SKELETON, UNTESTED ON MAC
  lipflow-upstream/         # vendored Lipflow reference (MIT), read-only
  tests/                    # pure-Python tests (run on Linux)
  docs/FAST_SETUP_PLAN.md
```

## Models (see MODELS.md for sizes, SHA, licenses)

| Model | Source | Use |
|---|---|---|
| Auto-AVSR visual-only, LRS3 19.1% WER | Amanvir/LRS3_V_WER19.1 (HF) | Main lip reader |
| Subword RNN LM | Amanvir/lm_en_subword (HF) | Beam search LM |
| SentencePiece unigram5000 | mpc001/auto_avsr (GitHub) | LM tokenizer |
| MediaPipe FaceLandmarker | Google MediaPipe (storage.googleapis.com) | Live landmarks |
| Auto-AVSR audio-visual (whisper mode, 1.8 GB) | nguyenvulebinh/auto_avsr_av_trlrwlrs2lrs3vox2avsp_base (HF) | Lips + whisper audio |
| Qwen3-0.6B 4-bit MLX | mlx-community/Qwen3-0.6B-4bit (HF) | Offline cleanup |
| Qwen3-1.7B 4-bit MLX | mlx-community/Qwen3-1.7B-4bit (HF) | Cleanup fallback |
| AV-HuBERT Large | vumichien/AV-HuBERT (HF) | Backup VSR encoder only |

**License warning:** the LRS3-trained Auto-AVSR weights are for
**non-commercial research use only** (Lipflow README + NOTICE). Code is
MIT / Apache 2.0, weights are not. Do not ship this commercially with
those weights. See LICENSES.md.

## Charging — blocked until the LRS3 licence is resolved

**Paid version is blocked. Do not ship or charge for Subvox Local
with the current weights.** The LRS3 Auto-AVSR weights (visual-only
+ audio-visual, plus the subword LM) are non-commercial research
use only — see LICENSES.md and `docs/CHARGING_PLAN.md`.

Proposed pricing (not final, changeable in one place):
7-day free trial, no card upfront, then **$12/month** or
**$99 one-time lifetime** (`PRICE_MONTHLY_USD=12`,
`PRICE_LIFETIME_USD=99`). Trial ends = dictation stops, setup
and transcripts stay. Licence keys are offline-first
(`SUBVOX-XXXX-XXXX-XXXX` format, key file in Application
Support, no audio sent during licence checks). Checkout is a
placeholder only (`https://example.com/checkout`) — no real
checkout, Stripe key, or licence server exists in this repo.

Full plan, including the commercial path (licence / swap model /
train own / ship research-only free now, paid later), what Francis
still needs (Apple Developer $99/yr, payment provider account,
commercial model + pricing decisions, support email, refund policy),
and risks (Intel i5 CPU latency vs Wispr cloud speed, Wispr and
Superwhisper competition, 6 GB download): `docs/CHARGING_PLAN.md`.

Note: Francis's Mac is an **Intel Core i5, not Apple Silicon** —
MLX does not run on Intel, so the Mac path is PyTorch CPU +
GGUF Qwen cleanup, and latency / accuracy on that Mac are still
unmeasured. The "Apple Silicon" quick-start lines above are stale
on that point; see `docs/CHARGING_PLAN.md` §6–§7.

## What works / what is untested

Works here (Linux VM, verified in this build):
- Model downloads (exact Lipflow URLs, resumable) — see MODELS.md for
  final sizes once downloads finish.
- Pure-Python tests: `python -m pytest tests/` — viseme coverage,
  WER math, offline cleanup rules, no-cloud-import check.
- `python -m py_compile` on all new Python files.
- `subvox-local doctor` logic (model presence checks) — needs models
  present; run it on the Mac after setup.

UNTESTED ON INTEL MAC (needs Francis's Mac, Intel Core i5):
- PyTorch CPU inference of Auto-AVSR, beam search timing, LoRA training
  time / WER on held-out clips. LoRA is CPU-only — expect stage 1 to
  take longer than the ~2 min Apple Silicon target. Measure it; do not
  trust the old target.
- The whole packaging flow: `packaging/build_app.sh` (PyInstaller +
  swiftc), `packaging/build_dmg.sh` (hdiutil), first-launch model
  download, launcher symlink, Gatekeeper on the unsigned .app.
  This Linux VM cannot build or test any of it (no Xcode, no macOS).
- Camera capture, MediaPipe live tracking, hotkey, paste at cursor,
  menu-bar Swift app (still a skeleton — see packaging/README.md).
- GGUF Qwen cleanup via llama.cpp: LANDED 2026-10-31 (Intel backend
  lane) — `cleanup.py` uses llama-cpp + `models/qwen3-0.6b-gguf/
  Qwen3-0.6B-Q4_K_M.gguf` (unsloth, 379 MB, sha256 in MODELS.md).
  UNTESTED ON INTEL MAC: no GGUF inference run has happened on a Mac
  yet; the file + code are verified on the Linux VM only.
- The 2-minute fast-setup claim — measure it on the Mac,
  do not trust it until then. Record stock vs adapted WER in the setup report.

## No cloud

Dictation never touches the network. The only network use is the
one-time model download in `setup_macos.sh` / `scripts/download-models.sh`.
No API keys, no OpenAI/Anthropic calls, no telemetry.
