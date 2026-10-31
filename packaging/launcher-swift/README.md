# SubvoxLauncher — minimal compiled launcher (fallback entry point)

**UNTESTED ON MAC.** Written on a Linux VM (no `swiftc` here). Nothing in
this folder has ever been compiled. The first run of `build-launcher.sh`
on a Mac is the test.

## Why this exists

The hand-built click-to-open `.app` (`~/workspace/subvox-local-click`,
now retired) had `CFBundleExecutable` = a 499-byte bash script
(`Contents/MacOS/SubvoxLocal` execing `install.sh`). macOS Launch
Services treated it as a script to edit, so double-clicking it opened
**Script Editor** instead of running the app, and Gatekeeper rejected
it ("Apple could not verify Subvox Local is free of malware"). A `.app`
whose executable is a script is broken by design.

The fix is that `CFBundleExecutable` must be a **compiled Mach-O
binary**. The normal build already does that: `packaging/build_app.sh`
compiles the full 15-file SwiftUI app with `swiftc` into
`Contents/MacOS/SubvoxLocal`. This launcher is the **fallback** for the
day that SwiftUI binary is ever unusable: a tiny Foundation-only Swift
program that launches whatever is in the bundle, with no Terminal, no
Script Editor, and no silent failure.

## Files

| File | What it is |
|---|---|
| `main.swift` | The launcher. Foundation only, no SwiftUI/AppKit import, top-level code. Must stay named `main.swift` (top-level code only compiles in a file with that name). |
| `build-launcher.sh` | Compiles it with `swiftc -O -target x86_64-apple-macosx14.0` and verifies the output is a Mach-O 64-bit x86_64 binary (`file` + `lipo`). Fails the build if it is not. |
| `README.md` | This file. |

## Build (on the Intel Mac)

```sh
./packaging/launcher-swift/build-launcher.sh
# -> build/SubvoxLauncher (Mach-O 64-bit executable x86_64)
```

Smoke-test the binary standalone (it needs a bundle to do anything
real, so point it at a built `.app`):

```sh
SUBVOX_BUNDLE_PATH="build/Subvox Local.app" ./build/SubvoxLauncher
# Expect: the SwiftUI app opens (if SubvoxLocalUI exists, see below),
# or a macOS alert. Check ~/Library/Logs/SubvoxLocal/launcher.log.
```

## What the launcher does

1. Finds its bundle (`Bundle.main`, or `$SUBVOX_BUNDLE_PATH` for testing).
2. If `Contents/MacOS/SubvoxLocalUI` exists and is executable, launches
   it with `Process` and exits. That is the normal path.
3. Otherwise, runs `Contents/Resources/launcher.sh` (model download on
   first launch, then `subvox-local doctor`) and shows a macOS alert
   saying the backend is ready but the full UI binary is missing, with
   the rebuild command.
4. If neither exists, shows an alert saying the `.app` is incomplete
   and how to rebuild. It never fails silently.

It invokes `launcher.sh` from compiled code — that is fine. Launch
Services only cares that `CFBundleExecutable` itself is a Mach-O
binary, not that the binary never runs a script.

## Fallback .app layout (only if the SwiftUI binary is ever unusable)

```sh
# 1. Build the normal .app first, then the launcher:
./packaging/build_app.sh
./packaging/launcher-swift/build-launcher.sh

# 2. Swap the entry point: SwiftUI binary becomes the sibling,
#    the launcher becomes the executable (same name, same Info.plist):
APP="build/Subvox Local.app"
mv "$APP/Contents/MacOS/SubvoxLocal" "$APP/Contents/MacOS/SubvoxLocalUI"
cp build/SubvoxLauncher "$APP/Contents/MacOS/SubvoxLocal"
chmod +x "$APP/Contents/MacOS/SubvoxLocal" "$APP/Contents/MacOS/SubvoxLocalUI"

# 3. Verify the executable is a real binary, never a script:
file "$APP/Contents/MacOS/SubvoxLocal"
#    must say: Mach-O 64-bit executable x86_64
lipo -archs "$APP/Contents/MacOS/SubvoxLocal"   # must list x86_64

# 4. Re-image and install as usual:
./packaging/build_dmg.sh
```

Do **not** do this swap routinely. The normal build (SwiftUI binary as
`CFBundleExecutable`) is the supported path; this swap is only the
emergency fallback if `swiftc` of the full app fails and Francis needs
a working double-clickable `.app` while the SwiftUI failure is fixed.

## Why it is not wired into build_app.sh / CI yet

On purpose. Until this file has compiled cleanly **once on a real
Mac**, wiring it into `build_app.sh` (which runs under `set -e`) would
risk breaking the build path that is currently green (backend +
PyInstaller + full SwiftUI app all compile in CI run 10). The wiring
step, once the first Mac compile passes, is small:

1. In `build_app.sh` step 3, after the SwiftUI `swiftc`, add:
   `swiftc -O -target x86_64-apple-macosx14.0 -sdk "$SDK" -o "$BUILD/swift/SubvoxLauncher" packaging/launcher-swift/main.swift`
2. In step 4, also copy it to `$APP/Contents/MacOS/SubvoxLauncher`.
3. In the GitHub workflow, extend the "Verify the .app" step to check
   both binaries with `file` + `lipo`.

Do not wire it in before step 1 has passed on a Mac at least once.
