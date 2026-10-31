#!/usr/bin/env bash
# Subvox Local — macOS INTEL (x86_64) setup.
# Installs: uv + Python deps (CPU torch only, NO MLX — MLX does not run
# on Intel), core models (~1.22 GB) via the first-launch downloader,
# then runs doctor.
# Run on Francis's Intel Mac (macOS 14+, camera). NOT on Linux, NOT on
# Apple Silicon (use ./setup_apple_silicon.sh there).
# Usage:
#   git clone <this repo> ~/code/subvox-local && cd ~/code/subvox-local
#   ./setup_intel_macos.sh            # full setup, core models only
#   ./setup_intel_macos.sh --with-av  # also download the 1.8 GB AV whisper model
#
# UNTESTED ON INTEL MAC: written on a Linux VM. First run on the Mac
# will show what actually breaks — most likely the LoRA training time
# (CPU only, no MPS/MLX) and any import that assumed Apple Silicon.
#
# What this does NOT do (known gaps, see packaging/README.md):
#   * No .app/.dmg — that is packaging/build_app.sh + build_dmg.sh.
#     This script is the dev/CLI setup; the .app is the one-click path.
# GGUF cleanup IS landed (2026-10-31, Intel backend lane): cleanup.py
# now uses llama-cpp-python + models/qwen3-0.6b-gguf/Qwen3-0.6B-Q4_K_M.gguf
# (unsloth/Qwen3-0.6B-GGUF — the official Qwen GGUF repo has no Q4_K_M
# file). Downloaded below if missing; see docs/INTEL_MAC.md.
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: setup_intel_macos.sh is for macOS Intel only."
  echo "On this Linux VM, run: python3 -m pytest tests/   (pure-Python tests only)"
  echo "and: bash scripts/download-models.sh   (models only, no MLX / no app)"
  exit 1
fi
if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "ERROR: Intel (x86_64) required. This Mac is $(uname -m)."
  echo "For Apple Silicon, run: ./setup_apple_silicon.sh"
  exit 1
fi
echo "Intel Mac ($(uname -m)), macOS $(sw_vers -productVersion) — CPU-only backend, no MLX."

if ! command -v uv >/dev/null; then
  echo "Installing uv (Python package manager)…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo "NOTE: Xcode Command Line Tools not found. Needed for the Swift menu-bar app:"
  echo "  xcode-select --install"
fi

# Python 3.11–3.12 (pyproject requires >=3.11,<3.13).
uv python install 3.12 2>/dev/null || true
uv sync

# llama-cpp-python is a real dependency in pyproject.toml (Intel backend
# lane, 2026-10-31); `uv sync` above installs it. No separate pip install.
# GGUF cleanup model (Qwen3-0.6B Q4_K_M, ~379 MB) — download if missing.
# Source: unsloth/Qwen3-0.6B-GGUF (verified 2026-10-31; the official
# Qwen/Qwen3-0.6B-GGUF repo ships only Q8_0, no Q4_K_M file).
GGUF_DIR="$PWD/models/qwen3-0.6b-gguf"
GGUF_FILE="$GGUF_DIR/Qwen3-0.6B-Q4_K_M.gguf"
if [ ! -s "$GGUF_FILE" ]; then
  mkdir -p "$GGUF_DIR"
  echo "Downloading GGUF cleanup model (~379 MB)…"
  curl -fL --retry 3 --retry-delay 5 -C - -o "$GGUF_FILE.part" \
    https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf \
    && mv "$GGUF_FILE.part" "$GGUF_FILE"
  echo "✓ cleanup model (Qwen3-0.6B-Q4_K_M GGUF, llama-cpp CPU)"
else
  echo "✓ GGUF cleanup model already present: $GGUF_FILE"
fi

# Core models (~1.22 GB) into the repo models/ dir for CLI use.
# The installed .app downloads into ~/Library/Application Support instead
# (first-launch downloader); this dev setup keeps weights in the repo.
DL_ARGS=(--models-dir "$PWD/models")
if [[ "${1:-}" == "--with-av" ]]; then
  DL_ARGS+=(--include-av)
  echo "Also downloading the 1.8 GB AV whisper model (--with-av)."
fi
# --include-qwen-gguf is passed for the .app downloader path; the GGUF
# file for CLI use was already downloaded above (this script's own step).
python3 packaging/first_launch_downloader.py "${DL_ARGS[@]}" --include-qwen-gguf

# Verify
uv run python -m subvox_local doctor

echo
echo "Done. Next, on this Mac:"
echo "  1. Grant permissions when asked: Camera, Input Monitoring, Accessibility"
echo "  2. Fast setup:  uv run python -m subvox_local setup-fast"
echo "     NOTE: LoRA training is CPU-only on Intel — expect it to take"
echo "     LONGER than the ~2 min Apple Silicon target. Time it; do not"
echo "     trust the old target until measured."
echo "  3. Train personal LM:   uv run python -m subvox_local train-lm   (after importing text)"
echo "  4. Dictate: hold Right Option anywhere, mouth words, release."
echo "  5. One-click .app build: ./packaging/build_app.sh && ./packaging/build_dmg.sh"
echo "See README.md and packaging/README.md for the full plan and Mac test steps."
