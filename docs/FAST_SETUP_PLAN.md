# Fast setup plan — cut Lipflow's 8 minutes without losing quality

> **INTEL MAC CORRECTION (2026-10-31):** Francis's Mac is an Intel Core
> i5, NOT Apple Silicon. MLX does not run on Intel Macs, so the MLX
> cleanup and "~2 min" claims in this doc do NOT apply to his laptop.
> Intel path: GGUF Qwen3 via llama-cpp (CPU), torch CPU, LoRA 150 steps
> default, stage 2 in background. See `docs/INTEL_MAC.md` — that doc
> supersedes this one for anything about speed or setup time on Intel.
> This doc is kept for the sentence/LoRA design rationale only.

## What Lipflow does (stock, ~8 min)

1. Permissions (Camera, Input Monitoring, Accessibility) — once.
2. Import Wispr Flow dictation history locally (optional, zero mouthing).
3. Practice: mouth **24 sentences** (12 of your own + 12 Harvard).
4. Train: fine-tune the **language model** on your phrasing (3 epochs),
   and fine-tune the **lip reader front end + first encoder layer**
   for 6 epochs on all 24 clips — about 5 minutes on an M4 Pro GPU.
   Six sentences are held out; the face model is kept only if it reads
   them better than stock.

Total: ~8 minutes. The training is the long pole, and the 24 takes are
the boring pole.

## What the fast plan changes (target: ~2 min to usable)

| Step | Stock (Lipflow) | Fast plan (this repo) | Why quality holds |
|---|---|---|---|
| Sentences | 24 (12 own + 12 Harvard) | **10 Harvard, all visemes covered** (`src/subvox_local/sentences.py`) | Harvard sentences are phonetically balanced by design (IEEE 1969). 10 chosen sentences cover all 10 viseme classes — verified by `tests/test_sentences.py`. Your own sentences are *better* for vocabulary, worse for coverage; we get vocabulary from the LM instead (below). |
| Stage 1 takes | 24 | **6 sentences (~2 min)** | The 6 quick sentences alone cover all 10 viseme classes (verified). Each take is ~6 s of mouthing + ~2 s overhead. |
| Face training | Full front end + encoder layer 1, 6 epochs, 24 clips | **LoRA only, rank 8, ~0.6M params, max 300 steps** (`src/subvox_local/adapt.py`) | Freezing the base and training only attention Q/K/V/out adapters is the published speaker-adaptation result (KAIST 2024, "V LoRA +0.6M"): 1 minute of adaptation data improved every speaker. Same loss (0.1·CTC + 0.9·attention), same augmentation, BatchNorm frozen — only the trainable set is smaller, so it trains faster and forgets less. |
| LM training | 3 epochs on your phrases | **Same, unchanged** — and it costs zero mouthing | This is the biggest accuracy win per minute: your phrasing + names. Import text first (`subvox-local import-text`), train LM in the background while you do stage 1. |
| Held-out check | 6 of 24 held out, keep if better | **2 of the 10 held out in stage 1, keep only if WER beats stock** | Smaller held-out set is noisier — say so at setup time. Stage 2 re-checks on all 10 + corrections. If stage 1 does not beat stock, the stock model stays; nothing is lost. |
| Stage 2 | Re-run full setup | **Background: other 4 sentences + corrections, continue LoRA from stage 1** | You are already dictating while stage 2 trains. No second 8-minute wait. |
| Cleanup | Top-3 + LLM rerank | **Same: top-3 beam + local Qwen3-0.6B MLX rerank** | This is where homophene errors (p/b/m, f/v) get fixed. Unchanged. |

## The 10 sentences (and what each covers)

See `src/subvox_local/sentences.py` for the list with per-sentence notes.
Viseme classes: M=p/b/m, F=f/v, T=t/d/n/s/z, K=k/g, J=ch/sh/j,
W=r/w, A=a/e, I=i/ee, U=o/u, D=th. Verified: `python -m pytest tests/test_sentences.py`.

Quick 6 (stage 1): indices 0, 2, 4, 5, 8, 9 of the 10.
Stage 2: indices 1, 3, 6, 7 + correction clips.
Held out in stage 1: indices 3 and 7 (never trained on in stage 1).

## What is NOT cut (and why)

- **Held-out keep/drop check.** Cutting it would let a bad adapt ship.
  It stays, even though 2 held-out sentences is noisier than 6.
- **LM training.** It is cheap and it is where "your words" come from.
- **Top-3 + LLM cleanup.** Raw VSR output is uppercase guesses with
  homophene errors; without cleanup it reads wrong even when the model
  is right about the lip shapes.
- **0.4 s trailing frames.** The model needs frames after the last word.
- **Face alignment to the mean face.** The model was trained on aligned
  96×96 crops; skipping alignment would cost more accuracy than any
  training trick saves.

## Mac test steps (Apple Silicon, macOS 14+, camera)

These have NOT been run in this build (Linux VM, no MLX/MPS). Run them
on Francis's Mac and record the actual numbers — do not trust the
targets below until measured.

1. `./setup_macos.sh` — expect ~5 GB downloads, `doctor` all ok.
2. `uv run python -m subvox_local doctor` — all models present.
3. `uv run python -m subvox_local setup-fast --dry-run` — lists 6 sentences, no camera.
4. `uv run python -m subvox_local setup-fast` — time it. Target: stage 1
   (6 takes + LoRA 300 steps + held-out eval) under ~4 minutes total
   including the takes. Record: stock WER, adapted WER, kept? (yes/no),
   train seconds, step count.
5. `uv run python -m subvox_local file <test-video.mp4>` — decode a
   known clip, compare to the known text, record WER.
6. Silent mouthing test: mouth "The birch canoe slid on the smooth planks"
   3 times, record what comes out (raw + cleaned) each time.
7. Whisper mode (optional): needs models/av/model.safetensors (1.8 GB).
   Lipflow reports lips-only 31.9% WER vs lips+audio 6.9% on test
   sentences — re-measure on your own clips, do not quote Lipflow's
   numbers as yours.
8. If LoRA does not beat stock on held-out: keep stock, run
   `subvox-local adapt-more` (stage 2, 4 more sentences + corrections),
   re-evaluate. If it still does not beat stock, the honest answer is
   "stock + personal LM + cleanup" — that is still the best local
   silent-dictation setup in this repo.

## Risks / honest limits

- Silent mouthing is harder than filmed speech: smaller lip movements.
  Lipflow's 19.1% WER is on LRS3 (clearly filmed speech), not silent
  webcam mouthing. Expect worse on your own webcam; measure it.
- 2 held-out sentences is a noisy keep/drop test. Stage 2 re-checks.
- LoRA rank 8 is a guess from the paper, not a tuned value for this
  checkpoint. If stage 1 underperforms, try rank 16 / 600 steps before
  falling back to Lipflow's full-frontend fine-tune.
- Qwen3-0.6B cleanup is tiny; it fixes homophenes and casing, it does
  not rescue a badly mis-read sentence. The 1.7B fallback is in models/
  for that case.
- LRS3 weights are non-commercial research only (see LICENSES.md).
  This build is for Francis's own use / research. Do not ship it
  commercially with those weights.
