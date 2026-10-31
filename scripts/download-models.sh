#!/usr/bin/env bash
# Download ALL models for Subvox Local.
# Sources: Lipflow scripts/download-models.sh + lipflow/av.py + lipflow/cleanup.py
# (Amanvir LRS3_V_WER19.1, Amanvir lm_en_subword, mpc001 unigram5000,
#  nguyenvulebinh AV model, MediaPipe face_landmarker, mlx-community Qwen3,
#  vumichien AV-HuBERT). No URLs invented — every URL below is from those files.
# Run from repo root: bash scripts/download-models.sh
# Resumable: re-running skips files that already exist and are non-empty.
set -euo pipefail
cd "$(dirname "$0")/.."

get() {  # url dest
  if [ -s "$2" ]; then echo "✓ $2 (already present, $(du -h "$2" | cut -f1))"; return; fi
  mkdir -p "$(dirname "$2")"
  echo "↓ $2"
  curl -fL --retry 3 --retry-delay 5 -C - -o "$2.part" "$1" && mv "$2.part" "$2"
}

HF=https://huggingface.co

# --- 1. Auto-AVSR visual-only, LRS3, 19.1% WER (Lipflow's main model) ---
get $HF/Amanvir/LRS3_V_WER19.1/resolve/main/model.json models/vsr/model.json
get $HF/Amanvir/LRS3_V_WER19.1/resolve/main/model.pth  models/vsr/model.pth
# --- 2. Subword RNN language model for beam search ---
get $HF/Amanvir/lm_en_subword/resolve/main/model.json  models/lm/model.json
get $HF/Amanvir/lm_en_subword/resolve/main/model.pth   models/lm/model.pth
# --- 3. SentencePiece tokenizer (needed to train LM / adapt on your phrases) ---
get https://github.com/mpc001/auto_avsr/raw/main/spm/unigram/unigram5000.model models/lm/unigram5000.model
# --- 4. MediaPipe face landmarker ---
get https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task \
    models/face_landmarker.task
# --- 5. Auto-AVSR audio-visual model (whisper mode, optional, 1.8 GB) ---
get $HF/nguyenvulebinh/auto_avsr_av_trlrwlrs2lrs3vox2avsp_base/resolve/main/config.json models/av/config.json
get $HF/nguyenvulebinh/auto_avsr_av_trlrwlrs2lrs3vox2avsp_base/resolve/main/model.safetensors models/av/model.safetensors
# --- 6. Qwen3-0.6B 4-bit MLX (offline cleanup, ~350 MB) ---
# APPLE SILICON ONLY — MLX does not run on Intel Macs. Kept for
# reference; the Intel build uses section 9 (GGUF) instead.
for f in config.json model.safetensors tokenizer.json tokenizer_config.json vocab.json merges.txt added_tokens.json special_tokens_map.json; do
  get $HF/mlx-community/Qwen3-0.6B-4bit/resolve/main/$f models/qwen3-0.6b-4bit-mlx/$f
done
# --- 7. Qwen3-1.7B 4-bit MLX (fallback cleanup, larger / more accurate) ---
# APPLE SILICON ONLY — see section 6 note.
for f in config.json model.safetensors tokenizer.json tokenizer_config.json vocab.json merges.txt added_tokens.json special_tokens_map.json; do
  get $HF/mlx-community/Qwen3-1.7B-4bit/resolve/main/$f models/qwen3-1.7b-4bit-mlx/$f
done
# --- 8. AV-HuBERT Large backup (vumichien/AV-HuBERT, model.pt) ---
# NOTE: Lipflow does NOT use this file. It is a backup/alternative VSR encoder only.
# The repo's README describes it as AV-HuBERT weights from the original paper
# (LRS3 433h + VoxCeleb2). No size is listed on the HF page; download and check.
get $HF/vumichien/AV-HuBERT/resolve/main/model.pt models/avhubert/model.pt
# --- 9. Qwen3-0.6B Q4_K_M GGUF (INTEL MAC cleanup, ~379 MB) ---
# Primary cleanup model on Intel Macs: GGUF via llama-cpp-python, CPU.
# CORRECTION (verified 2026-10-31 via HF API file list): the official
# Qwen/Qwen3-0.6B-GGUF repo ships ONLY Qwen3-0.6B-Q8_0.gguf — there is
# NO Q4_K_M file there. The Q4_K_M build lives in unsloth/Qwen3-0.6B-GGUF
# (also lmstudio-community/Qwen3-0.6B-GGUF). Downloaded 2026-10-31:
# 396,705,472 bytes, sha256 ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a.
get $HF/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf models/qwen3-0.6b-gguf/Qwen3-0.6B-Q4_K_M.gguf
# --- 10. Qwen3-1.7B Q4_K_M GGUF (Intel fallback cleanup, larger / more accurate) ---
# Optional; only downloaded if the 0.6B GGUF is not accurate enough.
get $HF/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf models/qwen3-1.7b-gguf/Qwen3-1.7B-Q4_K_M.gguf

echo
echo "Done. Sizes:"
du -sh models/* 2>/dev/null; du -sh models
