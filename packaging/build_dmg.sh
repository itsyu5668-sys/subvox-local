#!/usr/bin/env bash
# Subvox Local — one-command .dmg from the built .app.
#   ./packaging/build_dmg.sh [--layout]
#
# Run on the Intel Mac after ./packaging/build_app.sh.
# Creates a compressed, drag-to-install DMG:
#   build/Subvox Local.dmg
# containing:
#   * Subvox Local.app
#   * a symlink to /Applications (drag the app onto it to install)
#
# Models are NOT in the .dmg — on purpose. The full model set is
# ~6.24 GB (and the Intel core set alone is ~1.22 GB). Bundling them
# would make the download enormous and every app update would
# re-download gigabytes of unchanged weights. Instead the app
# downloads models once, on first launch, into
# ~/Library/Application Support/Subvox Local/models/ (resumable,
# SHA-verified — see packaging/first_launch_downloader.py).
#
# --layout: also set the Finder window layout (icon positions,
# window size) via AppleScript. Cosmetic only; skipped by default
# because it needs Finder automation and a mounted volume dance.
# The DMG installs fine without it.
#
# UNTESTED ON INTEL MAC: written on a Linux VM (no hdiutil here).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build"
APP="$BUILD/Subvox Local.app"
DMG="$BUILD/Subvox Local.dmg"
STAGING="$BUILD/dmg-staging"
VOLNAME="Subvox Local"

LAYOUT=0
for a in "$@"; do
  case "$a" in
    --layout) LAYOUT=1 ;;
    *) echo "Unknown flag: $a (use --layout)"; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: build_dmg.sh needs macOS (hdiutil). This Linux VM cannot build a .dmg."
  exit 1
fi
if [[ ! -d "$APP" ]]; then
  echo "ERROR: $APP not found. Run ./packaging/build_app.sh first."
  exit 1
fi

echo "== Subvox Local .dmg build =="
echo "App size: $(du -sh "$APP" | cut -f1)  (models NOT included — see header comment)"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/Subvox Local.app"
ln -s /Applications "$STAGING/Applications"

# Optional: code-sign the .app before imaging (unsigned by default).
# If SIGN_IDENTITY is set (e.g. "Developer ID Application: Francis Ezeudu (TEAMID)"),
# sign the whole bundle with the entitlements first. See packaging/README.md.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "Signing .app with: $SIGN_IDENTITY"
  codesign --force --options runtime --entitlements packaging/SubvoxLocal.entitlements \
      --sign "$SIGN_IDENTITY" "$STAGING/Subvox Local.app"
  codesign --verify --verbose "$STAGING/Subvox Local.app"
else
  echo "NOTE: building UNSIGNED (no SIGN_IDENTITY set). Gatekeeper will"
  echo "block a plain double-click on other Macs — right-click > Open works."
  echo "See packaging/README.md for the signing/notarization checklist."
fi

hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" \
    -ov -format UDZO -imagekey zlib-level=9 "$DMG"

if [[ "$LAYOUT" == "1" ]]; then
  echo "Applying Finder layout (icon positions)…"
  MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG" \
      | grep -E '^/dev' | sed 's/.*\/Volumes\//\/Volumes\//')"
  osascript <<EOF
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 100, 900, 450}
    set the icon size of the icon view options of container window to 96
    set position of item "Subvox Local.app" of container window to {150, 180}
    set position of item "Applications" of container window to {350, 180}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF
  hdiutil detach "$MOUNT"
  # Re-compress read-only after the layout pass.
  mv "$DMG" "$BUILD/Subvox Local-rw.dmg"
  hdiutil convert "$BUILD/Subvox Local-rw.dmg" -format UDZO \
      -imagekey zlib-level=9 -o "$DMG"
  rm "$BUILD/Subvox Local-rw.dmg"
fi

echo
echo "Done: $DMG"
echo "Size:     $(du -h "$DMG" | cut -f1)"
echo "SHA-256:  $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "Verify:   hdiutil verify \"$DMG\""
echo
echo "Install test (on the Intel Mac):"
echo "  1. Open the .dmg, drag Subvox Local.app to Applications."
echo "  2. Right-click the app > Open (first run, unsigned)."
echo "  3. Grant Camera / Input Monitoring / Accessibility when asked."
echo "  4. First launch downloads ~1.22 GB of models — watch progress in"
echo "     ~/Library/Application Support/Subvox Local/download-progress.json"
echo "  5. Run the launcher smoke test:"
echo "     /Applications/Subvox\\ Local.app/Contents/Resources/launcher.sh doctor"
