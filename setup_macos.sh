#!/usr/bin/env bash
# Subvox Local — macOS setup dispatcher.
#   Intel (x86_64, Francis's Mac) -> ./setup_intel_macos.sh
#   Apple Silicon (arm64)         -> ./setup_apple_silicon.sh (reference only; MLX)
# Run on the Mac (macOS 14+, camera). NOT on Linux.
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: setup_macos.sh is for macOS only."
  echo "On this Linux VM, run: python3 -m pytest tests/   (pure-Python tests only)"
  echo "and: bash scripts/download-models.sh   (models only, no app)"
  exit 1
fi
case "$(uname -m)" in
  x86_64) exec ./setup_intel_macos.sh "$@" ;;
  arm64)  exec ./setup_apple_silicon.sh "$@" ;;
  *) echo "ERROR: unsupported architecture: $(uname -m)"; exit 1 ;;
esac
