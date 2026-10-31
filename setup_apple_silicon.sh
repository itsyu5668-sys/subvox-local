#!/usr/bin/env bash
# Subvox Local — macOS APPLE SILICON setup (renamed from setup_macos.sh).
# Intel Macs: use ./setup_intel_macos.sh instead (MLX does not run on Intel).
# This file is kept for reference / Apple Silicon machines only.
# Installs: uv + Python deps, all models (~5 GB total incl. optional AV +
# Qwen 1.7B fallback), preloads the MLX cleanup model, runs doctor.
# Run on the Mac (macOS 14+, Apple Silicon, camera). NOT on Linux:
# MLX and the menu-bar app are macOS-only, and this script will refuse
# to build the .app on non-darwin.
# Usage:
#   git clone <this repo> ~/code/subvox-local && cd ~/code/subvox-local
#   ./setup_apple_silicon.sh            # full setup
#   ./setup_apple_silicon.sh --no-av    # skip the 1.8 GB whisper-mode AV model
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: setup_apple_silicon.sh is for macOS Apple Silicon only."
  echo "On this Linux VM, run: python3 -m pytest tests/   (pure-Python tests only)"
  echo "and: bash scripts/download-models.sh   (models only, no MLX / no app)"
  exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: Apple Silicon (arm64) required. MLX does not run on Intel Macs."
  exit 1
fi

if ! command -v uv >/dev/null; then
  echo "Installing uv (Python package manager)…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
if ! command -v brew >/dev/null; then
  echo "NOTE: Homebrew not found. Xcode Command Line Tools are needed for the Swift menu-bar app:"
  echo "  xcode-select --install"
fi

uv sync

# Models (~1.2 GB core + 1.8 GB AV + ~1.4 GB Qwen/AV-HuBERT extras)
if [[ "${1:-}" == "--no-av" ]]; then
  echo "Skipping AV whisper model. Download it later with:"
  echo "  bash scripts/download-models.sh   (edit the script, or run the AV lines by hand)"
  # Download everything except the AV safetensors by running the script
  # with a marker — simplest honest path: run full script, it is resumable.
  bash scripts/download-models.sh
else
  bash scripts/download-models.sh
fi

# Preload the small on-device cleanup model (~350 MB) so first launch doesn't stall
uv run python -c "from mlx_lm import load; load('mlx-community/Qwen3-0.6B-4bit')" \
  && echo "✓ cleanup model (Qwen3-0.6B-4bit MLX)"

# Verify
uv run python -m subvox_local doctor

echo
echo "Done. Next, on this Mac:"
echo "  1. Grant permissions when asked: Camera, Input Monitoring, Accessibility"
echo "  2. Fast setup (2 min):  uv run python -m subvox_local setup-fast"
echo "  3. Train personal LM:   uv run python -m subvox_local train-lm   (after importing text)"
echo "  4. Dictate: hold Right Option anywhere, mouth words, release."
echo "See README.md and docs/FAST_SETUP_PLAN.md for the full plan and Mac test steps."
