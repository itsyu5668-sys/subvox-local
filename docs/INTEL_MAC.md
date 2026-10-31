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

## How to run on the Intel Mac

```sh
./setup_macos.sh
# 1. Grant Camera, Input Monitoring, Accessibility when asked
# 2. Check the backend:
uv run python -m subvox_local doctor
#    expect: qwen3-0.6b-gguf ... ok, ~379 MB; llama_cpp importable;
#    mlx_lm "not used on Intel Mac"
# 3. Fast setup (SLOW on i5 — start it and wait, do not expect 2 min):
uv run python -m subvox_local setup-fast
# 4. Personal LM (optional, biggest accuracy win):
uv run python -m subvox_local import-text my-writing.txt
uv run python -m subvox_local train-lm
# 5. Dictate: hold Right Option anywhere, mouth words, release.
#    Or test a file: uv run python -m subvox_local file talk.mp4
```

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
- `device='mps'` / CUDA errors — nothing in this build asks for MPS or
  CUDA. If you see one, an old config or old code is running; pull
  latest and check `load_reader(device=...)` calls.

## Intel Mac test steps (NOT yet run — record real numbers here)

1. `./setup_macos.sh` — expect ~6.6 GB downloads total, `doctor` all ok.
2. `uv run python -m subvox_local doctor` — GGUF ok, llama_cpp importable.
3. `uv run python -m subvox_local setup-fast --dry-run` — lists 6 sentences, no camera.
4. `uv run python -m subvox_local setup-fast` — TIME IT. Record: stock
   WER, adapted WER, kept? (yes/no), train seconds, step count.
   Do NOT expect ~2 min; record whatever it actually takes.
5. Cleanup timing: time `clean_top3` on a known top-3 (or one
   dictation) — record GGUF seconds per sentence on the i5.
6. `uv run python -m subvox_local file <test-video.mp4>` — decode a
   known clip, record WER and total seconds from release to text.
7. Silent mouthing test: mouth "The birch canoe slid on the smooth
   planks" 3 times, record raw + cleaned output each time.
8. If LoRA does not beat stock on held-out: keep stock, run
   `subvox-local adapt-more` (stage 2, background), re-evaluate.
   If it still does not beat stock, the honest answer is
   "stock + personal LM + GGUF cleanup".
