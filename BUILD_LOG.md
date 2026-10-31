# Build log — Subvox Local (2026-10-31)

## Sources (exact, no invented URLs)
- Lipflow: https://github.com/amywork777/lipflow (cloned to lipflow-upstream/)
- Subvox: https://github.com/joeblau/subvox (in /tmp/subvox, reference only)
- Model URLs: Lipflow scripts/download-models.sh, lipflow/av.py, lipflow/cleanup.py, setup.sh

## Models downloaded (verify with `python3 scripts/model_inventory.py`)
- models/vsr/model.json — 5,512 B, Amanvir/LRS3_V_WER19.1 — OK
- models/vsr/model.pth — 1,001,908,942 B (~956 MB), PK zip magic — OK
- models/lm/model.json — 951 B, Amanvir/lm_en_subword — OK
- models/lm/model.pth — 215,076,928 B (~206 MB), PK zip magic — OK
- models/lm/unigram5000.model — 319,?? B (320K), mpc001/auto_avsr — OK
- models/face_landmarker.task — 3,758,596 B, MediaPipe — OK
- models/av/config.json — 1,407 B, nguyenvulebinh AV model — OK
- models/av/model.safetensors — DOWNLOADING (1.8 GB expected)
- models/qwen3-0.6b-4bit-mlx/* — QUEUED (after AV)
- models/qwen3-1.7b-4bit-mlx/* — QUEUED (after AV)
- models/avhubert/model.pt — QUEUED (after Qwen, backup only)

Download command (resumable): `bash scripts/download-models.sh`
Log: models/download.log (curl progress — very verbose, use `ls -lh` not `tail`)

## Code written (this build)
- src/subvox_local/: paths, visemes, sentences, capture, face, vsr,
  adapt (LoRA), cleanup (offline, MLX + rules), lm_train, corrections,
  dictation, paste, app, __main__
- tests/: test_sentences.py, test_cleanup.py
- setup_macos.sh, pyproject.toml, scripts/download-models.sh,
  scripts/model_inventory.py
- swift/SubvoxLocalApp.swift (skeleton, UNTESTED ON MAC)
- README.md, LICENSES.md, MODELS.md (generated), docs/FAST_SETUP_PLAN.md

## Update 2026-10-31 ~06:05 UTC (coordinator)
- Lipflow inspector handoff received (agent 3f91e9be): HEAD e37453b1e1e125ca7130e4abf2635117635f6e0b, MIT code, LRS3 weights non-commercial research only (confirmed in README + NOTICE). Confirms our exact URL list. Extra findings to note: AV model is NOT in setup.sh (lazy download on first Whisper-mode enable, 1.8 GB, and its "resumable" download is NOT resumable — ours is, curl -C -); Qwen3 preload failure is silent in Lipflow setup.sh; safetensors is an undeclared direct dep in Lipflow (transitive only); beam defaults disagree (LipReader 20 / app 4 / file 10) — we pin 10.
- Download hiccup: AV model.safetensors curl died at ~186 MB with `curl: (18) transfer closed with 1582191994 bytes remaining`. Restarted with nohup (resumable .part, ~2.4 MB/s). Recovered; that was the only curl error in the whole run.
- pytest: 7 passed after fixing test_no_cloud_imports — it asserted the words "anthropic"/"openai" appear nowhere, but cleanup.py + pyproject.toml mention them in comments saying NOT to use them. Test now checks for actual imports (`import/from anthropic|openai`) and API-key env vars. 7 passed, 0 failed.
- adapt-more CLI runner IMPLEMENTED (was a stub): records the 4 STAGE2 sentences, trains 150 steps continuing from stage-1 LoRA if present, includes saved stage-1 clips + correction clips, evaluates on saved held-out clips with keep-only-if-better, saves unconditionally only if no held-out clips exist (says so). setup-fast now also saves held-out clips as h*.npz so stage 2 has a real gate. Dry-run verified: `PYTHONPATH=src python3 -m subvox_local adapt-more --dry-run` exit 0.
- Code reviewer handoff received (agent 1a95ac33, 06:04 UTC): 16 findings, all addressed. Blockers fixed: LoRA params created on base layer device (was a guaranteed MPS crash); train_lora empty-clip guard; adapter grads re-enabled so stage 2 can train; load_reader redirects Lipflow personal paths to Subvox home + loads saved LoRA on launch (before: adapting then relaunching silently discarded the adapt); train-lm ensures models symlink before importing Lipflow trainer; Wispr import redirected to Subvox phrases; CLIPS_DIR created before saving; 25 fps resample in capture.record() and file mode; year cleanup fixed (ninety, round decades, hundreds); LocalCleaner checks a model is actually downloaded, loads from local dir, falls back to rules on load failure; dead sleep removed; read_top3 dead beam_size param removed; import-wispr CLI added; paste.py double-print fixed; LoRALinear is now a real nn.Module subclass; word_error_rate moved to torch-free wer.py so tests stay torch-free. Reviewer also confirmed LoRA math (589,824 params), viseme coverage, and paths.
- After the review fixes, one self-inflicted regression caught by tests: adapt.py's new top-level torch import broke test_wer (no torch on this VM) and the dry-runs. Fixed by moving word_error_rate to wer.py and moving dry-run checks before heavy imports. Re-verified: py_compile OK, pytest 7 passed, both dry-runs exit 0.

## Downloads COMPLETE 2026-10-31 ~06:31 UTC — 6.24 GB catalogued
All files in models/, verified by scripts/model_inventory.py (MODELS.md regenerated with real sizes + sha256 prefixes):
- vsr/model.pth 1001.9 MB (PK zip magic), lm/model.pth 215.1 MB, unigram5000.model 0.3 MB, face_landmarker.task 3.8 MB
- av/model.safetensors 1776.4 MB — safetensors header parses, 1381 tensors
- qwen3-0.6b-4bit-mlx/ 8 files, 351 MB — safetensors header parses, 705 tensors
- qwen3-1.7b-4bit-mlx/ 8 files, 984 MB — safetensors header parses, 705 tensors
- avhubert/model.pt 1928.1 MB (PK zip magic, backup only)
- `subvox-local doctor` on this VM: every model reports ok.

## Verified on this Linux VM
- py_compile on all new Python files: OK
- pytest: 7 passed, 0 failed (2026-10-31 ~06:03 UTC, re-run after review fixes ~06:35 UTC)
- Model file headers (PK zip / safetensors headers parse / task bundle) + JSON configs parse: OK
- Viseme coverage: FAST_10 and QUICK_6 cover all 10 classes (verified
  against Lipflow's viseme mapper)
- AV config: adim 768, aheads 12, elayers 12 — matches LoRA math
  (4 linears x 12 layers x r=8 x 768 x 2 = 589,824 params)

## NOT verified (needs Mac, Apple Silicon)
- torch / MPS inference, beam search, LoRA training time + WER
- MLX Qwen cleanup, camera, hotkey, paste, Swift menu-bar app
- The 2-minute fast-setup claim
- Model file headers (PK zip / task bundle) + JSON configs parse: OK
- Viseme coverage: FAST_10 and QUICK_6 cover all 10 classes (verified
  against Lipflow's viseme mapper)
- AV config: adim 768, aheads 12, elayers 12 — matches LoRA math
  (4 linears x 12 layers x r=8 x 768 x 2 = 589,824 params)

## NOT verified (needs Mac, Apple Silicon)
- torch / MPS inference, beam search, LoRA training time + WER
- MLX Qwen cleanup, camera, hotkey, paste, Swift menu-bar app
- The 2-minute fast-setup claim

## License warning
LRS3 weights: non-commercial research only. See LICENSES.md.
