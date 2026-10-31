#!/usr/bin/env bash
# Subvox Local — one-command .app build for an INTEL Mac.
#   ./packaging/build_app.sh [--skip-backend] [--skip-swift]
#
# Run on Francis's Intel Mac (macOS 14+, Xcode Command Line Tools,
# Python 3.11–3.12, uv). NOT on Linux, NOT on Apple Silicon.
# (Apple Silicon: ./setup_apple_silicon.sh — different backend, MLX.)
#
# What it does, in order:
#   1. Checks: Darwin, x86_64 Intel, xcode-select, python3, uv.
#      Refuses arm64 (wrong script — MLX path is separate) and Linux.
#   2. Builds the Python backend with PyInstaller (one-dir, x86_64,
#      CPU torch, llama-cpp, mediapipe, vendored lipflow/espnet).
#      Models are NOT bundled — they download on first launch.
#   3. Compiles the SwiftUI menu-bar app with swiftc (there is no
#      .xcodeproj yet — all 12 files in swift/*.swift are compiled
#      together as one module).
#      Once an Xcode project exists, replace step 3 with xcodebuild
#      (see the commented block below).
#   4. Assembles Subvox Local.app with Info.plist + entitlements,
#      embeds the backend in Contents/Resources/subvox-backend/,
#      copies launcher.sh + first_launch_downloader.py into Resources/.
#   5. Runs `subvox-local doctor` from the bundle as a smoke test
#      (models are expected to be missing at this point — the smoke
#      test only checks the binary starts; full doctor runs on first
#      launch after the model download).
#
# Output: build/Subvox Local.app
# Next step: ./packaging/build_dmg.sh
#
# UNTESTED ON INTEL MAC: written on a Linux VM (no Xcode, no macOS
# toolchain here). The first run on the Mac will almost certainly need
# fixes — missing hidden imports in the PyInstaller spec, swiftc
# flags, or both. That is normal; fix, rebuild, re-run.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build"
APP="$BUILD/Subvox Local.app"

SKIP_BACKEND=0; SKIP_SWIFT=0
for a in "$@"; do
  case "$a" in
    --skip-backend) SKIP_BACKEND=1 ;;
    --skip-swift)   SKIP_SWIFT=1 ;;
    *) echo "Unknown flag: $a (use --skip-backend / --skip-swift)"; exit 2 ;;
  esac
done

echo "== Subvox Local .app build (Intel Mac, x86_64) =="
echo "UNTESTED ON INTEL MAC — first run, expect fixes."

# --- 1. Platform checks -------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: build_app.sh must run on a Mac. This Linux VM cannot build a .app."
  exit 1
fi
ARCH="$(uname -m)"
if [[ "$ARCH" != "x86_64" ]]; then
  echo "ERROR: this script builds the INTEL (x86_64) app; this Mac is $ARCH."
  echo "For Apple Silicon, use ./setup_apple_silicon.sh (MLX backend)."
  exit 1
fi
echo "✓ Intel Mac ($ARCH), $(sw_vers -productVersion)"
if ! xcode-select -p >/dev/null 2>&1; then
  echo "ERROR: Xcode Command Line Tools not found. Run: xcode-select --install"
  exit 1
fi
if ! command -v uv >/dev/null; then
  echo "Installing uv…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
if ! command -v swiftc >/dev/null; then
  echo "ERROR: swiftc not found. Install Xcode Command Line Tools: xcode-select --install"
  exit 1
fi
echo "✓ CLT + uv + swiftc present"

# --- 2. Python backend (PyInstaller, one-dir) ---------------------------
if [[ "$SKIP_BACKEND" == "0" ]]; then
  echo
  echo "== Backend: PyInstaller (CPU torch, no MLX) =="
  # CPU-only torch: PyPI macOS wheels are CPU-only already (CUDA wheels
  # are Linux-only), so plain `uv sync` is enough. llama-cpp-python is
  # NOT in pyproject.toml yet (the GGUF cleanup branch hasn't landed);
  # install it into the build venv so the spec's hidden import resolves.
  uv sync
  uv pip install llama-cpp-python pyinstaller
  echo "NOTE: MLX is deliberately excluded — it has no x86_64 wheels."
  uv run pyinstaller packaging/PyInstaller.spec --noconfirm \
      --distpath "$BUILD/dist" --workpath "$BUILD/pyinstaller"
  if [[ ! -x "$BUILD/dist/subvox-local/subvox-local" ]]; then
    echo "ERROR: PyInstaller output missing: $BUILD/dist/subvox-local/subvox-local"
    exit 1
  fi
  echo "✓ backend built: $BUILD/dist/subvox-local/ ($(du -sh "$BUILD/dist/subvox-local" | cut -f1))"
else
  echo "== Backend skipped (--skip-backend) — reusing previous build =="
  [[ -x "$BUILD/dist/subvox-local/subvox-local" ]] || {
    echo "ERROR: no previous backend build found."; exit 1; }
fi

# --- 3. SwiftUI menu-bar app -------------------------------------------
if [[ "$SKIP_SWIFT" == "0" ]]; then
  echo
  echo "== Swift app: swiftc (no .xcodeproj yet) =="
  # Full 12-file SwiftUI app — compile ALL swift/*.swift together as one
  # module. (An older version of this script compiled only
  # SubvoxLocalApp.swift; that no longer works — the app is 12 files now.)
  # -target pins Intel; -O optimises.
  # If this fails with a MenuBarExtra / SwiftUI error, the fix is an
  # Xcode project (see the xcodebuild block below) — not a swiftc flag.
  SDK="$(xcrun --show-sdk-path)"
  mkdir -p "$BUILD/swift"
  swiftc -O -target x86_64-apple-macosx14.0 \
      -sdk "$SDK" \
      -o "$BUILD/swift/SubvoxLocal" \
      swift/*.swift
  echo "✓ Swift binary: $BUILD/swift/SubvoxLocal"
else
  echo "== Swift skipped (--skip-swift) — reusing previous binary =="
  [[ -x "$BUILD/swift/SubvoxLocal" ]] || {
    echo "ERROR: no previous Swift binary found."; exit 1; }
fi

# --- 4. Assemble the .app bundle ---------------------------------------
echo
echo "== Assembling Subvox Local.app =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/swift/SubvoxLocal" "$APP/Contents/MacOS/SubvoxLocal"
cp packaging/Info.plist "$APP/Contents/Info.plist"
cp -R "$BUILD/dist/subvox-local" "$APP/Contents/Resources/subvox-backend"
cp packaging/launcher.sh "$APP/Contents/Resources/launcher.sh"
cp packaging/first_launch_downloader.py "$APP/Contents/Resources/first_launch_downloader.py"
chmod +x "$APP/Contents/MacOS/SubvoxLocal" \
         "$APP/Contents/Resources/launcher.sh" \
         "$APP/Contents/Resources/subvox-backend/subvox-local"
# Remove quarantine-prone junk if any crept in.
find "$APP" -name ".DS_Store" -delete 2>/dev/null || true

# --- 5. Smoke test ------------------------------------------------------
echo
echo "== Smoke test: bundled backend starts =="
# Models are NOT in the bundle, so `doctor` will report missing models —
# that is expected here. What must NOT happen: a crash / missing-library
# error before doctor prints anything.
if "$APP/Contents/Resources/subvox-backend/subvox-local" doctor 2>&1 | tee "$BUILD/smoke-doctor.log"; then
  echo "✓ doctor ran (it will list missing models until first launch downloads them)"
else
  echo "NOTE: doctor exited non-zero — check $BUILD/smoke-doctor.log."
  echo "If it complains about missing MODELS, that is expected pre-first-launch."
  echo "If it complains about missing .dylib / .so / import errors, the"
  echo "PyInstaller spec needs more hidden imports — fix and rebuild."
fi

echo
echo "Done: $APP  ($(du -sh "$APP" | cut -f1))"
echo "Next: ./packaging/build_dmg.sh"
echo
echo "KNOWN GAPS (do not ship until fixed):"
echo "  * Live dictation bridge still missing: BackendBridge launches"
echo "    'uv run python -m subvox_local' and never calls launcher.sh;"
echo "    the Python JSON-lines streaming mode does not exist yet."
echo "    Until that lands, test the backend by hand:"
echo "      \"$APP/Contents/Resources/launcher.sh\" doctor"
echo "  * Qwen3 GGUF file is chosen (unsloth/Qwen3-0.6B-GGUF,"
echo "    Qwen3-0.6B-Q4_K_M.gguf) but first_launch_downloader.py still"
echo "    has url=null for it — first launch will not download it."
echo "  * License key accepts any non-empty key (placeholder);"
echo "    CHECKOUT_URL is empty. No real activation yet."
echo "  * App is UNSIGNED. See packaging/README.md signing checklist"
echo "    before giving the .dmg to anyone else."

# --- xcodebuild path (for when swift/ becomes a real Xcode project) -----
# Once swift/SubvoxLocal.xcodeproj exists, replace step 3 above with:
#   xcodebuild -project swift/SubvoxLocal.xcodeproj \
#       -scheme SubvoxLocal -configuration Release \
#       -arch x86_64 -derivedDataPath "$BUILD/xcode" \
#       build
#   cp "$BUILD/xcode/Build/Products/Release/SubvoxLocal.app/Contents/MacOS/SubvoxLocal" \
#      "$BUILD/swift/SubvoxLocal"
# xcodebuild also signs the Swift binary if a Developer ID identity is
# configured; the whole-bundle codesign still happens in build_dmg.sh
# (or a later sign step) — never sign the binary twice.
