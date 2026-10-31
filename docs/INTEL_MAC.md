# Intel Mac (Core i5) — what changed vs Apple Silicon

**UNTESTED ON INTEL MAC:** everything in this doc about Francis's laptop
is code + reasoning, not a measured run. Nothing below was run on an
Intel Mac in this build (Linux VM only). Record the real numbers on his
Mac and update this doc — do not trust any estimate here until measured.

## The correction

Francis's Mac is an **Intel Core i5, NOT Apple Silicon**. MLX is Apple
Silicon only and does not run on Intel Macs. The previous Apple Silicon
plan (MLX cleanup, MPS torch, "~2 min" fast setup) is dead for his
laptop. Proof in one line: MLX is Apple Silicon only; on Intel the
replacements are llama.cpp / Ollama CPU, and GGUF runs everywhere.

## What changed

| Piece | Apple Silicon (old, dead for this Mac) | Intel i5 (now) |
|---|---|---|
| Cleanup LLM | Qwen3-0.6B 4-bit via MLX (`mlx-community/Qwen3-0.6B-4bit`, ~350 MB), ~0.2 s/sentence | Qwen3-0.6B Q4_K_M GGUF via llama-cpp-python, CPU, local file `models/qwen3-0.6b-gguf/Qwen3-0.6B-Q4_K_M.gguf` (396,705,472 bytes, sha256 `ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a`) |
| Cleanup fallback | Qwen3-1.7B 4-bit MLX | Qwen3-1.7B Q4_K_M GGUF (`unsloth/Qwen3-1.7B-GGUF`, not yet downloaded) |
| VSR torch device | MPS (Apple GPU) | CPU only — `load_reader()` defaults to `device="cpu"`, `"auto"` resolves to CPU, MPS/CUDA requests are rejected loudly |
| LoRA training | 300 steps, M4 Pro GPU | 150 steps default, batch 1, 0 workers, torch threads capped at 4, CPU only |
| Stage 2 adapt | Re-run in foreground | Background thread (`adapt.start_stage2_background`), checkpoint every 50 steps, resumable |
| Python deps | `mlx-lm` | `llama-cpp-python` (MLX removed from `pyproject.toml`) |
| Setup script | `setup_macos.sh` required arm64, preloaded MLX | Requires x86_64, refuses arm64, preloads the GGUF via llama-cpp |

Files changed: `src/subvox_local/cleanup.py`, `adapt.py`, `vsr.py`,
`paths.py`, `app.py` (doctor + setup wording), `pyproject.toml`,
`setup_macos.sh`, `scripts/download-models.sh` (section 9 GGUF),
`MODELS.md`, `tests/test_cleanup.py` (fallback test is now deterministic
+ a no-MLX-import test), this doc. Swift UI / packaging untouched.
Train First + live dictation (2026-10-31): new
`src/subvox_local/stream.py` (`dictate-stream` / `serve`, JSON lines),
`app.py` gains `dictate-stream`, `serve`, `record-one`, `test-sentence`
and `setup-fast --non-interactive --clip-dir --takes --steps
--reuse-clips` (+ `adapt-more --non-interactive`); Swift
`BackendBridge.DictationSession` now launches `dictate-stream` and
parses its JSON lines, `DictationView` pastes cleaned text at the
cursor and shows measured latency/confidence, `SetupView` is Train
First (10 sentences x 3 takes, per-sentence `record-one`, 3x birch
test), `AppState` defaults to the Setup tab, onboarding ends at Setup.
License key validation is real (format + checksum, test key
`SUBVOX-7K2Q-9M4D-8X3Y` validates) — see `swift/LicenseManager.swift`.

## GGUF source correction

The brief named repo `Qwen/Qwen3-0.6B-GGUF` for the Q4_K_M file. That
repo does NOT contain it — verified 2026-10-31 via the Hugging Face API
file list, it ships only `Qwen3-0.6B-Q8_0.gguf`. The Q4_K_M build was
downloaded from `unsloth/Qwen3-0.6B-GGUF`
(`https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf`).
Manual link if the download ever needs repeating:
https://huggingface.co/unsloth/Qwen3-0.6B-GGUF (file `Qwen3-0.6B-Q4_K_M.gguf`).
Alternative mirror: `lmstudio-community/Qwen3-0.6B-GGUF` (same filename).

## Expected latency — honest numbers

Source for the Lipflow figures: `lipflow-upstream/README.md`, "Speed
(M4 Pro, 9 s utterance)": encoder **0.16 s on the Apple GPU, 1.7 s on
CPU**; beam search about **0.8–1.6 s on CPU**; about **1–2 s from
release to text** on the M4 Pro.

What that means on an Intel i5:

- **VSR encode:** at least the 1.7 s CPU figure, plausibly several
  seconds for a 9 s utterance — the i5 is a much weaker CPU than an
  M4 Pro, and there is no GPU to fall back to. Expect dictation to
  feel slower than the 1–2 s M4 Pro total. No i5 number is claimed
  here; measure it (test 4 below).
- **Beam search:** 0.8–1.6 s on CPU (Lipflow's figure, CPU already) —
  roughly the same ballpark on the i5, maybe slower.
- **GGUF cleanup:** one short generation (max 60 tokens) from a 0.6B
  Q4 model on CPU. Slower than MLX on Apple Silicon (~0.2 s/sentence
  there). No number claimed until measured — could be well under a
  second or a few seconds depending on the i5. Measure it (test 5).
  *VM data point (NOT an i5 measurement):* on the Linux build VM on
  2026-10-31, `clean_top3` with the real GGUF file returned the
  correct sentences ("While in office.", "Born in New York City.")
  in 3.5 s including model load and 2.1 s warm per sentence. That VM's
  CPU is not Francis's i5 — treat it only as proof the code path
  works end to end, not as an i5 latency promise.
- **Total per dictation:** expect several seconds on the i5 vs ~1–2 s
  on an M4 Pro. That is the honest trade for a CPU-only laptop.

## CPU LoRA training time — expectations

- LoRA is still rank 8, **589,824 trainable params** — the parameter
  count is unchanged; only the speed changes.
- Lipflow's full fine-tune took ~5 minutes of GPU training on an M4
  Pro; the old LoRA 300-step target was ~2 minutes on that GPU.
- On an i5 CPU the same steps will be **much slower — several times
  slower at best, plausibly 10+ minutes for stage 1** (150 steps).
  No total time is claimed until measured. Do NOT quote "2 min" on Intel.
- That is why stage 1 defaults to **150 steps** (not 300), why
  `train_lora()` saves a checkpoint every 50 steps and can resume from
  one (`resume_path=`), and why stage 2 runs in a background thread
  (`start_stage2_background`) while the user keeps dictating with the
  stock model. If stage 1 is still too slow, drop to 75–100 steps
  before touching rank (rank 8 is from the KAIST paper, not tuned).
- The keep-only-if-better gate is unchanged: the adapted model is
  saved ONLY if held-out WER beats stock. A slow train that does not
  help costs time, not accuracy.

## The script .app is retired (2026-10-31)

The hand-built click-to-open `.app` (CFBundleExecutable = a bash
script) opened Script Editor on double-click and was rejected by
Gatekeeper. It is retired — see the top of `packaging/README.md`.
Only two builds are supported now: the GitHub Actions `.dmg`
artifact, or `./packaging/build_app.sh` + `./packaging/build_dmg.sh`
on the Intel Mac. Both fail loudly if the executable is ever a script
again (`build_app.sh` step 4b, workflow "Verify CFBundleExecutable"
step). The compiled fallback entry point, if the SwiftUI binary is
ever unusable, is `packaging/launcher-swift/` (minimal Foundation-only
Swift binary — UNTESTED ON MAC, not wired into the build yet).

## How to run on the Intel Mac

```sh
./setup_macos.sh
# 1. Grant Camera, Input Monitoring, Accessibility when asked
# 2. Check the backend:
uv run python -m subvox_local doctor
#    expect: qwen3-0.6b-gguf ... ok, ~379 MB; llama_cpp importable;
#    mlx_lm "not used on Intel Mac"
# 3. TRAIN FIRST (step 1, before dictation — stock Auto-AVSR is not
#    accurate on a new face; the personal LoRA is the accuracy fix):
uv run python -m subvox_local setup-fast --non-interactive \
    --clip-dir ~/Library/Application\ Support/SubvoxLocal/clips/fast_setup \
    --takes 3 --steps 150
#    Records the 10 Harvard sentences, 3 takes each (30 clips, ~6 s
#    each). Takes 1-2 train the LoRA (rank 8, 589,824 params); take 3
#    of each sentence is held out for the keep gate. Training is SLOW
#    on an i5 CPU — plausibly 10+ minutes for 150 steps. Do NOT expect
#    2 minutes. The report at the end prints the MEASURED train seconds.
#    If it is interrupted, re-run the same command with --reuse-clips
#    to keep already-recorded takes, and training resumes from the
#    checkpoint saved every 50 steps.
# 4. Personal LM (optional, biggest accuracy win after the LoRA):
uv run python -m subvox_local import-text my-writing.txt
uv run python -m subvox_local train-lm
# 5. Test it — mouth the birch sentence 3 times, stock vs adapted:
uv run python -m subvox_local test-sentence --takes 3 --non-interactive
#    Prints per-run raw / cleaned / WER / latency, plus stock_wer,
#    adapted_wer and kept (yes/no). Same mouth clips decoded twice,
#    so the comparison is fair.
# 6. Dictate live (JSON lines, one per utterance):
uv run python -m subvox_local dictate-stream --seconds 10
#    Each line: {"event":"utterance","raw":...,"cleaned":...,
#    "top3":[...],"latency_s":...,"vsr_s":...,"cleanup_s":...,
#    "confidence":...} — latency_s is measured decode time only
#    (end of recording to cleaned text), confidence is top-3
#    agreement, not a calibrated probability. Expect several seconds
#    per utterance on the i5, not 1-2 s.
#    Or test a file: uv run python -m subvox_local dictate-stream --file talk.mp4
#    (or the older: uv run python -m subvox_local file talk.mp4)
#    Hold-to-talk in the app: hold Space/H or Right Option, release to decode.
```

### What to record (fill in on the Mac — no numbers here are measured yet)

| Measurement | Where it comes from | Record here |
|---|---|---|
| Train First: stock WER (held-out take 3, 10 clips) | `setup-fast --non-interactive` JSON report, `stock_wer` | |
| Train First: adapted WER | same report, `adapted_wer` | |
| Train First: kept? (yes/no) | same report, `kept` | |
| Train First: train seconds / steps | same report, `train.seconds` / `train.steps` (150 steps) | |
| Birch test x3: per-run raw / cleaned / WER / latency | `test-sentence` JSON report, `adapted_rows` / `stock_rows` | |
| Birch test: stock WER vs adapted WER, kept | same report, `stock_wer` / `adapted_wer` / `kept` | |
| Live dictation: latency per utterance | `dictate-stream` JSON lines, `latency_s` (+ `vsr_s`, `cleanup_s`) | |
| Live dictation: confidence per utterance | same lines, `confidence` (top-3 agreement) | |

In the app, the same numbers appear in Setup (stock/adapted WER, kept,
measured train seconds) and Dictate (decode time + confidence per
utterance). Nothing in the UI shows a number until the backend measures it.

Requirements: macOS 14+, Intel x86_64 (Core i5), camera, Python
3.11–3.12 (via `uv`), torch CPU wheel (installed by `uv sync` on
x86_64 macOS), llama-cpp-python (wheel; needs no build on macOS).

## What is slower, what still works

Slower on Intel: VSR encode (CPU vs Apple GPU), LoRA training
(CPU, 150 steps, background it), GGUF cleanup (CPU vs MLX).
Still works: everything else — MediaPipe face tracking, 96×96 mouth
crops at 25 fps, Auto-AVSR beam search top-3, offline rules fallback,
personal LM training (CPU, cheap), hold-to-talk dictation, paste at
cursor. No cloud anywhere: no OpenAI/Anthropic calls, no MLX.

## Troubleshooting

- `setup_macos.sh` says "Apple Silicon (arm64) required" — you are
  running the OLD script. Pull the latest repo; the Intel script
  requires x86_64 and refuses arm64.
- `doctor` says the GGUF file is MISSING — run
  `bash scripts/download-models.sh` (section 9, resumable) or
  download manually from https://huggingface.co/unsloth/Qwen3-0.6B-GGUF
  into `models/qwen3-0.6b-gguf/Qwen3-0.6B-Q4_K_M.gguf`.
- Cleanup falls back to basic rules (sentences come out with plain
  casing, no homophone fixing) — `llama_cpp` is not importable or the
  GGUF file is missing. Check `doctor`: `llama_cpp` must say
  importable and the GGUF line must say ok. Re-run `uv sync`.
- `llama-cpp-python` install fails on the Mac — it ships macOS wheels;
  make sure Python is 3.11–3.12 (`uv python --version`) and `uv sync`
  ran clean. Do not `pip install` it outside uv.
- Dictation is very slow (10+ s per sentence) — that is the expected
  CPU cost, not a bug, but record the actual timings (test 4/5) before
  deciding anything: the fix, if any, is a smaller beam, shorter
  utterances, or the 1.7B GGUF only if accuracy (not speed) is the
  problem — the 1.7B is slower, not faster.
- LoRA training seems stuck — it is probably just slow. Check the
  checkpoint file `~/Library/Application Support/SubvoxLocal/models/vsr_face_lora_stage1.pt`
  updates every 50 steps; if it updates, training is progressing.
  Kill it and resume with `resume_path=<checkpoint>` rather than
  starting over.
- `dictate-stream` prints `{"event":"error", ...}` and exits 1 —
  that is the honest failure path (missing camera / model / torch),
  not a bug. Read the `error` field; do not expect a transcript
  when the backend cannot run. It never fakes output.
- `device='mps'` / CUDA errors — nothing in this build asks for MPS or
  CUDA. If you see one, an old config or old code is running; pull
  latest and check `load_reader(device=...)` calls.

## Intel Mac test steps (NOT yet run — record real numbers here)

1. `./setup_macos.sh` — expect ~6.6 GB downloads total, `doctor` all ok.
2. `uv run python -m subvox_local doctor` — GGUF ok, llama_cpp importable.
3. `uv run python -m subvox_local setup-fast --dry-run` — lists 10 sentences, 3 takes each, no camera.
4. `uv run python -m subvox_local setup-fast --non-interactive --takes 3 --steps 150` — TIME IT. Record: stock
   WER, adapted WER, kept? (yes/no), train seconds, step count.
   Do NOT expect ~2 min; record whatever it actually takes (plausibly 10+ min).
5. Cleanup timing: time `clean_top3` on a known top-3 (or one
   dictation) — record GGUF seconds per sentence on the i5.
6. `uv run python -m subvox_local dictate-stream --file <test-video.mp4>` — decode a
   known clip, record WER and total seconds from release to text.
   Check each JSON line has raw / cleaned / top3 / latency_s / confidence.
7. Silent mouthing test: `uv run python -m subvox_local test-sentence --takes 3 --non-interactive`
   — mouth "The birch canoe slid on the smooth planks" 3 times, record
   per-run raw + cleaned + WER + latency, stock WER vs adapted WER, kept yes/no.
8. Live dictation in the app: hold Space/H or Right Option, release —
   cleaned text pastes at the cursor, raw/top-3/latency/confidence show
   in Dictate. If the backend is missing, the session fails loudly with
   the error, never a fake transcript.
9. If LoRA does not beat stock on held-out: keep stock, run
   `subvox-local adapt-more --non-interactive` (stage 2, background), re-evaluate.
   If it still does not beat stock, the honest answer is
   "stock + personal LM + GGUF cleanup".
