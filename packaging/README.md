# Subvox Local — packaging (Intel Mac one-click install)

**UNTESTED ON INTEL MAC.** Everything in this folder was written on a
Linux VM (no Xcode, no macOS toolchain). Nothing here has run on a Mac
yet. The first build on Francis's Intel Mac will need fixes — that is
expected, and the scripts say so where it matters.

## The one command (on Francis's Intel Mac)

```sh
cd ~/code/subvox-local        # or wherever the repo lives
./packaging/build_app.sh      # builds Subvox Local.app  (~10–30 min first time)
./packaging/build_dmg.sh      # builds Subvox Local.dmg from the .app
```

Then install it like any Mac app: open the `.dmg`, drag
**Subvox Local.app** onto **Applications**, double-click it.

### What you need before running it

| Need | Why | How to check / get |
|---|---|---|
| Intel Mac, macOS 14+ | MLX does not run on Intel; this is the Intel build | `uname -m` → `x86_64`, `sw_vers` → 14.x+ |
| Xcode Command Line Tools | `swiftc`, `xcrun`, `codesign`, `hdiutil` | `xcode-select --install` |
| Python 3.11–3.12 | Backend runtime | `python3 --version` (uv installs one if missing) |
| `uv` | Dependency + build venv | installed automatically by the script if missing |
| ~8 GB free disk | Build (~1–2 GB) + models (~1.22 GB core) + headroom | `df -h ~` |
| Internet | Model download on first launch (~1.22 GB core) | — |

### Time estimates (honest)

**torch on Intel macOS: PyTorch stopped shipping macOS x86_64 wheels
after 2.2.2.** `torch>=2.4` is arm64/Linux only — on an Intel Mac pip
says `No matching distribution found for torch>=2.4`. `pyproject.toml`
therefore pins `torch==2.2.2` on `darwin + x86_64` (found 2026-10-31
in CI run 41220859738). Do not "fix" the pin back to `>=2.4` without
checking PyPI for an x86_64 macOS wheel first.

**llama-cpp-python on Intel macOS: no prebuilt wheel exists.** PyPI
carries only sdists and the abetlen CPU wheel index ships macOS wheels
for arm64 only (checked 2026-10-31, all versions). It builds from
source, but the build fails linking the `llama-server` binary (httplib
TLS needs x86_64 OpenSSL symbols macOS does not provide). `build_app.sh`
therefore installs it with `CMAKE_ARGS="-DLLAMA_BUILD_SERVER=OFF"` —
Subvox never uses the server binary. If a future version ships an
Intel macOS wheel, the flag can go.

| Step | Time |
|---|---|
| `build_app.sh` first run (uv sync + torch + PyInstaller + swiftc) | ~10–30 min (mostly downloading torch) |
| `build_dmg.sh` | ~1–5 min (compression) |
| First-launch model download, core set ~1.22 GB | depends on internet: ~2 min at 100 Mbps, ~20 min at 10 Mbps |
| Fast setup (LoRA, 6 sentences, 300 steps) | **slower than the 2-minute Apple Silicon target — CPU only, no MPS/MLX. Measure it on the Mac; do not trust the old target.** |

## What is in the .dmg vs what downloads on first launch

**In the .dmg** (what you download once, ~0.8–1.5 GB — check with `du -sh` after the build):

- `Subvox Local.app` — the SwiftUI menu-bar app + the frozen Python
  backend (`Contents/Resources/subvox-backend/`, PyInstaller one-dir:
  CPU torch, llama-cpp, mediapipe, OpenCV, vendored Lipflow/ESPnet).
- `Contents/Resources/launcher.sh` — starts the backend, see below.
- `Contents/Resources/first_launch_downloader.py` — the model downloader.
- An `Applications` symlink (drag-to-install).

**NOT in the .dmg** (downloads on first launch, resumable, SHA-verified):

- Core models, ~1.22 GB: Auto-AVSR visual-only (`vsr/model.pth`,
  1,001.9 MB), subword LM (215.1 MB), SentencePiece tokenizer,
  MediaPipe FaceLandmarker. Without these the app cannot dictate.
- Optional, only if you ask: AV whisper model (1.8 GB), AV-HuBERT
  backup (1.9 GB). Not downloaded by default.
- **Qwen3 GGUF (Intel cleanup model): CHOSEN, but NOT downloaded by
  this script yet.** The file is `unsloth/Qwen3-0.6B-GGUF`,
  `Qwen3-0.6B-Q4_K_M.gguf`, and `src/subvox_local/cleanup.py` now has
  the llama.cpp branch for it. However `first_launch_downloader.py`
  still has the GGUF manifest entry as `url=null` and skips it with a
  warning — nobody has added the real download URL + SHA-256 to the
  downloader yet. Until that entry lands, first-launch cleanup on
  Intel uses offline rules only (sentence case, punctuation), not
  the LLM homophene fix. (The GGUF file can be fetched by hand with
  `bash scripts/download-models.sh`.)
- **Qwen3 MLX files (~1.3 GB): never downloaded on Intel.** MLX is
  Apple Silicon only; those weights would be dead weight.

Why models are not in the .dmg: 6.24 GB of weights would make the
download huge, and every app update would re-download gigabytes of
unchanged weights. Downloading once, on first launch, into
`~/Library/Application Support/Subvox Local/models/` keeps the .dmg
small and updates cheap.

First-launch flow: the app runs `launcher.sh`, which checks for the
core models, runs the downloader in the background if any are missing
(progress in `download-progress.json` in the same folder — the Swift
UI reads that file for its progress bar), symlinks the models dir
into the bundle (the backend resolves model paths from the bundle
root), then runs `subvox-local doctor`.

Pause / resume: create `~/Library/Application Support/Subvox Local/download.pause`
to pause, delete it to resume; re-running the downloader (or the
launcher) resumes any `.part` file. Cancel with the `.cancel` file
next to it, or Ctrl-C — partial files are kept.

## Files in this folder

| File | What it is |
|---|---|
| `build_app.sh` | One-command .app build (checks → PyInstaller backend → swiftc Swift app → bundle assembly → smoke test) |
| `build_dmg.sh` | One-command .dmg (staging → optional codesign → `hdiutil create` UDZO → SHA-256) |
| `PyInstaller.spec` | Backend spec: one-dir, x86_64, CPU torch, no MLX, hidden imports for vendored lipflow/espnet |
| `first_launch_downloader.py` | Stdlib-only model downloader: resumable, SHA-256 verified, progress JSON for the Swift UI |
| `launcher.sh` | Bundle launcher: models → symlink → doctor → backend subcommand |
| `Info.plist` | Bundle metadata (menu-bar only, camera usage string, macOS 14+) |
| `SubvoxLocal.entitlements` | Camera + unsigned-executable-memory + disable-library-validation (needed for torch/llama.cpp in a signed bundle) |

## How to test the install (on the Intel Mac)

```sh
# 1. Build + image
./packaging/build_app.sh
./packaging/build_dmg.sh

# 2. Install from the DMG (drag to Applications), then:
#    Right-click /Applications/Subvox Local.app > Open   (unsigned first run)

# 3. Backend smoke test (bypasses the Swift UI — the UI is now a full
#    12-file app, but the live-dictation bridge to the backend is still
#    missing, so the backend is still tested by hand here):
/Applications/Subvox\ Local.app/Contents/Resources/launcher.sh doctor
#    Expect: model download starts (~1.22 GB), then doctor lists models OK.

# 4. Dictation test (after models land):
/Applications/Subvox\ Local.app/Contents/Resources/launcher.sh file /path/to/test-video.mp4

# 5. Fast setup (time it — CPU LoRA will be slower than the Apple Silicon target):
/Applications/Subvox\ Local.app/Contents/Resources/launcher.sh setup-fast --dry-run
```

## Code-signing / notarization checklist

**Status right now: UNSIGNED. Do not claim otherwise.**

The .dmg built by default is unsigned. On Francis's own Mac, the
first launch needs **right-click → Open** (Gatekeeper blocks a plain
double-click on an unsigned app downloaded from the internet). That
is fine for personal testing. For anyone else — and before charging
money — it must be signed and notarized.

1. **Apple Developer account** — $99/year, enroll at
   developer.apple.com. You need a **Developer ID Application**
   certificate (for distribution outside the Mac App Store) and a
   Team ID.
2. **Sign the .app** — either set `SIGN_IDENTITY` when building the
   DMG (the script signs the whole bundle with the entitlements):
   ```sh
   SIGN_IDENTITY="Developer ID Application: Francis Ezeudu (TEAMID)" ./packaging/build_dmg.sh
   ```
   or sign by hand:
   ```sh
   codesign --force --options runtime \
     --entitlements packaging/SubvoxLocal.entitlements \
     --sign "Developer ID Application: Francis Ezeudu (TEAMID)" \
     "build/Subvox Local.app"
   codesign --verify --verbose "build/Subvox Local.app"
   ```
   (Use your real name + Team ID from the certificate, not the
   placeholder above.)
3. **Notarize** — Apple scans the signed app; without this, Gatekeeper
   still blocks it on other Macs even when signed:
   ```sh
   ditto -c -k --keepParent "build/Subvox Local.app" /tmp/SubvoxLocal.zip
   xcrun notarytool submit /tmp/SubvoxLocal.zip \
     --apple-id <your Apple ID> --team-id <TEAMID> --password <app-specific password> \
     --wait
   xcrun stapler staple "build/Subvox Local.app"
   spctl -a -vv "build/Subvox Local.app"   # should say "accepted"
   ```
   Notarization is per-build: re-do it for every new .dmg.
4. **Gatekeeper notes** — even signed + notarized, the first launch
   still asks for Camera, Input Monitoring, and Accessibility
   permission. Those are per-app, per-Mac; there is no way to
   pre-grant them in the installer.
5. **Do NOT ship a "signed" build until steps 2–4 actually pass.**
   A failed staple or a `spctl` rejection means it is not done.

## Troubleshooting

| Problem | Fix |
|---|---|
| Gatekeeper: "cannot be opened because the developer cannot be verified" | Unsigned build. Right-click the app → Open → Open. Or sign + notarize (checklist above). |
| "Subvox Local is damaged" after moving it | Usually a stale quarantine flag from an interrupted copy. `xattr -d com.apple.quarantine "/Applications/Subvox Local.app"` then retry. |
| Camera permission never asked / black preview | System Settings → Privacy & Security → Camera → enable Subvox Local. If it is not listed, launch the app once from Terminal so the prompt fires. |
| Hotkey (Right Option) does nothing | System Settings → Privacy & Security → Input Monitoring → enable Subvox Local; and Accessibility → enable it. Both are needed (hotkey tap + paste). Restart the app after granting. |
| Model download stalls / fails halfway | Re-run the launcher or the downloader — it resumes from `.part` files and skips verified files. Check `~/Library/Logs/SubvoxLocal/launcher.log`. A SHA mismatch deletes that file and retries once. |
| `doctor` says models missing right after download | Check the symlink: `ls -l "/Applications/Subvox Local.app/Contents/Resources/subvox-backend/models"` should point at `~/Library/Application Support/Subvox Local/models`. Re-run the launcher to recreate it. |
| PyInstaller build fails on a missing import | Read the build warnings, add the module to `hiddenimports` in `PyInstaller.spec`, rebuild. Do not hand-edit the frozen bundle. |
| `swiftc` fails | `swift/` is now 12 Swift files compiled together with `swiftc` (no `.xcodeproj` yet). Check the failing file's imports/flags first; moving to a real Xcode project is the fallback, not the first fix. |
| App launches but dictation output is wrong | Expected on first use — cleanup on Intel is offline rules until the GGUF model + llama.cpp branch land. Run fast setup first; that is the accuracy step. |

## Known gaps (do not ship until fixed)

1. **Swift app is now a FULL app (12 Swift files, Duna style), but the
   live-dictation bridge is still missing.** `swift/BackendBridge.swift`
   launches `uv run python -m subvox_local <command>` and parses JSON —
   it does NOT call `Contents/Resources/launcher.sh` and does NOT talk
   to the frozen PyInstaller backend bundled in the .app. There is no
   `launcher` reference anywhere in `swift/`. `DictationSession` needs
   a Python JSON-lines streaming mode that does not exist yet (the
   backend is a CLI: `doctor`, `setup-fast`, `file`, …). Until the
   bridge lands, the menu-bar UI cannot drive live dictation; test the
   backend by hand via `launcher.sh`.
2. **GGUF Qwen cleanup model: file CHOSEN, downloader entry still
   empty.** `unsloth/Qwen3-0.6B-GGUF`, `Qwen3-0.6B-Q4_K_M.gguf`,
   with a llama.cpp branch in `src/subvox_local/cleanup.py`. But
   `first_launch_downloader.py` still lists the GGUF entry as
   `url=null` and skips it, so first launch does not fetch it. Add
   the real URL + SHA-256 to the downloader manifest before claiming
   one-click install with full cleanup.
3. **License key is a placeholder.** `swift/LicenseManager.swift`
   accepts ANY non-empty key stored in the file (see the NOTE at the
   activation check), and `CHECKOUT_URL` is an empty placeholder
   Francis must fill in. There is no server-side verification, no
   Stripe check, no real activation. Do not charge anyone until a
   real license check exists.
4. **No daemon/serve mode.** The backend is a CLI (`doctor`,
   `setup-fast`, `file`, …). The launcher runs subcommands; a
   persistent backend process is pending the Swift socket bridge.
5. **No sandbox.** The entitlements deliberately skip
   `com.apple.security.app-sandbox` (camera + global hotkey + paste
   into other apps). Sandboxing is later hardening, not v0.1.
6. **LRS3 weights are non-commercial research only** (see
   LICENSES.md). Do not sell this with those weights — that license
   question is separate from the packaging and still open.
