#!/usr/bin/env bash
# SubvoxLauncher — compile the minimal compiled launcher binary.
#   ./packaging/launcher-swift/build-launcher.sh [output-path]
#
# Run on a Mac with Xcode Command Line Tools (swiftc). NOT on Linux.
# Default output: build/SubvoxLauncher
#
# What it does:
#   1. Compiles packaging/launcher-swift/main.swift with swiftc
#      (Foundation only — no SwiftUI, no AppKit, no -framework flags)
#      targeting x86_64-apple-macosx14.0, optimised.
#   2. Verifies the result really is a Mach-O 64-bit x86_64 binary
#      (file + lipo). A script, a text file, or an arm64 binary fails
#      the build here — that is the whole point of this launcher.
#
# STATUS: UNTESTED ON MAC. Written on a Linux VM (no swiftc here).
# The first run on a Mac is the test. If swiftc reports errors, fix
# main.swift; do NOT work around it by putting a script back as
# CFBundleExecutable — that is the bug this launcher exists to kill.
#
# The launcher is NOT wired into packaging/build_app.sh or the GitHub
# Actions workflow yet, on purpose: until it has compiled cleanly once
# on a real Mac, wiring it in would risk breaking the build path that
# is currently green (backend + PyInstaller + full SwiftUI app). The
# wiring step is documented in README.md in this folder.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"

OUT="${1:-$ROOT/build/SubvoxLauncher}"
mkdir -p "$(dirname "$OUT")"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: build-launcher.sh must run on a Mac (swiftc). This Linux VM cannot compile it."
  exit 1
fi
if ! command -v swiftc >/dev/null; then
  echo "ERROR: swiftc not found. Install Xcode Command Line Tools: xcode-select --install"
  exit 1
fi

echo "== SubvoxLauncher: swiftc (Foundation only, x86_64) =="
SDK="$(xcrun --show-sdk-path)"
swiftc -O -target x86_64-apple-macosx14.0 \
    -sdk "$SDK" \
    -o "$OUT" \
    packaging/launcher-swift/main.swift

echo "== Verifying: must be a Mach-O 64-bit x86_64 binary, never a script =="
file "$OUT"
if ! file "$OUT" | grep -q "Mach-O 64-bit executable x86_64"; then
  echo "ERROR: $OUT is not a Mach-O 64-bit x86_64 executable. Refusing to ship it."
  exit 1
fi
lipo -archs "$OUT" | grep -q x86_64 || {
  echo "ERROR: lipo does not list x86_64 for $OUT."
  exit 1
}
echo "✓ Compiled launcher: $OUT ($(du -h "$OUT" | cut -f1))"
echo "Next: see README.md in this folder for the fallback .app layout"
echo "and the one-command swap if the SwiftUI binary is ever unusable."
