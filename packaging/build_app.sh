#!/usr/bin/env bash
# Subvox Local — one-command .app build for an INTEL Mac.
#   ./packaging/build_app.sh [--skip-backend] [--skip-swift] [--allow-cross]
#
# Run on Francis's Intel Mac (macOS 14+, Xcode Command Line Tools,
# Python 3.11–3.12, uv). NOT on Linux, NOT on Apple Silicon — unless
# --allow-cross is passed (CI only): on an Apple Silicon Mac it
# cross-compiles the x86_64 app under Rosetta 2. That path needs
# X86_64_PYTHON set to an x86_64 python3.12 (e.g. the python.org
# universal2 install run under `arch -x86_64`) and is UNTESTED —
# it exists because GitHub removed the macos-13 Intel runner
# (see .github/workflows/build-macos-intel.yml).
# (Apple Silicon native: ./setup_apple_silicon.sh — different backend, MLX.)
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

SKIP_BACKEND=0; SKIP_SWIFT=0; ALLOW_CROSS=0
for a in "$@"; do
  case "$a" in
    --skip-backend) SKIP_BACKEND=1 ;;
    --skip-swift)   SKIP_SWIFT=1 ;;
    --allow-cross)  ALLOW_CROSS=1 ;;
    *) echo "Unknown flag: $a (use --skip-backend / --skip-swift / --allow-cross)"; exit 2 ;;
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
if [[ "$ARCH" == "x86_64" ]]; then
  echo "✓ Intel Mac ($ARCH), $(sw_vers -productVersion)"
elif [[ "$ALLOW_CROSS" == "1" ]]; then
  echo "NOTE: cross-compiling x86_64 on $ARCH via Rosetta 2 (--allow-cross)."
  echo "This is the CI fallback now that GitHub has no Intel runner."
  echo "The built .app is still x86_64 — it runs on Intel Macs, and"
  echo "under Rosetta on Apple Silicon. It is NOT an arm64 build."
  if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
    echo "ERROR: Rosetta 2 is not available. Run:"
    echo "  softwareupdate --install-rosetta --agree-to-license"
    exit 1
  fi
  if [[ -z "${X86_64_PYTHON:-}" ]]; then
    echo "ERROR: --allow-cross needs X86_64_PYTHON set to an x86_64"
    echo "python3.11/3.12 binary (e.g. the python.org universal2"
    echo "install, invoked as: arch -x86_64 <python>)."
    exit 1
  fi
  if [[ "$(arch -x86_64 "$X86_64_PYTHON" -c 'import platform; print(platform.machine())')" != "x86_64" ]]; then
    echo "ERROR: X86_64_PYTHON ($X86_64_PYTHON) is not an x86_64 interpreter."
    exit 1
  fi
  export UV_PYTHON="$X86_64_PYTHON"
  echo "✓ Rosetta + x86_64 python: $X86_64_PYTHON"
  echo "✓ Cross-compile host: $ARCH, $(sw_vers -productVersion) (target x86_64)"
else
  echo "ERROR: this script builds the INTEL (x86_64) app; this Mac is $ARCH."
  echo "For Apple Silicon, use ./setup_apple_silicon.sh (MLX backend)."
  echo "For CI cross-compile, pass --allow-cross (needs Rosetta + X86_64_PYTHON)."
  exit 1
fi
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
  # are Linux-only), so plain `uv sync` is enough.
  #
  # llama-cpp-python: there is NO prebuilt Intel macOS wheel (PyPI has
  # only sdists; the abetlen CPU wheel index ships macOS wheels for
  # arm64 only). So it builds from source.
  #
  # ROOT CAUSE of CI runs 5-6 (run 5 = 41222863743, run 6 = 41224744724):
  # the link that fails is NOT the llama-server binary — llama-cpp-python
  # never builds the server, and LLAMA_BUILD_SERVER already defaults OFF
  # when llama.cpp is built as a subdirectory. The failing target is
  # libllama-common (llama-cpp-python FORCE-builds it), which links
  # cpp-httplib; llama.cpp's LLAMA_OPENSSL defaults ON, so CMake found the
  # HOST's arm64 Homebrew OpenSSL 4.1.0 (/opt/homebrew/Cellar/openssl@4)
  # while targeting x86_64, and ld ignored both arm64 dylibs:
  #   ld: warning: ignoring file '.../libssl.dylib': found architecture
  #   'arm64', required architecture 'x86_64'
  #   ld: symbol(s) not found for architecture x86_64 (_X509_*, _SSL_* ...)
  # Subvox never uses HTTPS inside llama.cpp (local GGUF inference only),
  # so disable OpenSSL for the whole backend build. LLAMA_BUILD_SERVER=OFF
  # is kept as a belt-and-braces guard. This MUST be exported (not just set
  # on one pip line): `pip install -e .` and `uv sync` build
  # llama-cpp-python as a project dependency, and run 5 proved the
  # inline-only version never reaches that build.
  export CMAKE_ARGS="-DLLAMA_OPENSSL=OFF -DLLAMA_BUILD_SERVER=OFF"
  if [[ "$ALLOW_CROSS" == "1" ]]; then
    # CROSS-COMPILE PATH (Apple Silicon host -> x86_64 target).
    # uv cannot force an interpreter to run under Rosetta: a venv made
    # from the python.org universal2 python runs as arm64, and the first
    # CI attempt failed exactly there — PyInstaller collected an arm64
    # markupsafe .so and refused the x86_64 target
    # (IncompatibleBinaryArchError). So every Python invocation here goes
    # through `arch -x86_64`, and deps are installed with pip, not uv:
    # under Rosetta the universal2 interpreter reports x86_64 and pip
    # picks x86_64 wheels.
    XVENV="$ROOT/.venv-cross"
    rm -rf "$XVENV"
    arch -x86_64 "$X86_64_PYTHON" -m venv "$XVENV"
    XPY=(arch -x86_64 "$XVENV/bin/python")
    "${XPY[@]}" -c 'import platform; print("venv python arch:", platform.machine())'
    "${XPY[@]}" -m pip install --quiet --upgrade pip
    "${XPY[@]}" -m pip install -e "$ROOT"
    "${XPY[@]}" -m pip install llama-cpp-python pyinstaller
    echo "NOTE: MLX is deliberately excluded — it has no x86_64 wheels."
    "${XPY[@]}" -m PyInstaller packaging/PyInstaller.spec --noconfirm \
        --distpath "$BUILD/dist" --workpath "$BUILD/pyinstaller"
  else
    uv sync
    uv pip install llama-cpp-python pyinstaller
    echo "NOTE: MLX is deliberately excluded — it has no x86_64 wheels."
    uv run pyinstaller packaging/PyInstaller.spec --noconfirm \
        --distpath "$BUILD/dist" --workpath "$BUILD/pyinstaller"
  fi
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
