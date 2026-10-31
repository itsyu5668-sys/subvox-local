# Subvox Local — native SwiftUI app (macOS, Intel)

**Status: SOURCE ONLY, UNTESTED ON INTEL MAC.** This folder was written on a
Linux VM with no Xcode and no Swift toolchain for macOS. It has never been
compiled, run, or tested on any Mac. Do not ship it until the build and test
steps below have been run on Francis's Intel Core i5 Mac.

## What this is

A real macOS `.app`: menu-bar extra + main window, Duna style, driving the
Python backend in `src/subvox_local/` (PyTorch CPU + GGUF Qwen, local only).
The Swift app owns the window, the camera preview, the hotkey, the paywall,
and the settings. The Python backend owns all lip reading.

## Files

| File | What it is |
|---|---|
| `SubvoxLocalApp.swift` | `@main` App: `MenuBarExtra` + main `Window`, Duna nav bar (asterisk + SUBVOX wordmark, Dictate / Setup / Models / Settings), trial pill |
| `DunaTheme.swift` | Exact Duna tokens: Linen `#f7f7f5`, Paper `#ffffff`, Bone `#edece7`, Aubergine Ink `#1b0624`, Espresso `#160f0c`, Warm Ash `#766a7c`, Graphite `#444444`, Stone `#898683`, Mist `#eeeeee`, Onyx `#0d0d0d`, Smoke `#1a1816`, Charcoal `#292421`. GT America / Inter, pill buttons, 16px cards, 24px images, 8px inputs, 60px large buttons, 1px inset ring only, sunset watercolor as the only color moment |
| `AppState.swift` | Shared state: tab, settings (same `settings.json` the Python backend reads), doctor results, onboarding, download progress |
| `BackendBridge.swift` | Launches `uv run python -m subvox_local <command>` and parses JSON. Commands: `doctor`, `setup-fast`, `adapt-more`, `train-lm`, `import-text`, `import-wispr`, `file`. Also `DictationSession` — see the gap below |
| `LicenseManager.swift` | Trial + license key. Pricing constants in one place: `PRICE_MONTHLY_USD = 12`, `PRICE_LIFETIME_USD = 99`, trial 7 days, `CHECKOUT_URL` empty placeholder Francis must fill in |
| `CameraPreview.swift` | `AVCaptureSession` preview + 96×96 mouth-crop overlay |
| `DictationView.swift` | Dictation workspace: camera, live transcript, raw VSR line, top-3 hypotheses, paste target field, hold-to-talk (Space/H + Right Option), pipeline strip, honest latency readouts (no fake numbers) |
| `SetupView.swift` | Fast setup: Quick-6 Harvard sentences (indices 0,2,4,5,8,9), LoRA rank 8 / 589,824 params / 150 steps stage 1, keep-only-if-better gate with live-measured WER only |
| `ModelsView.swift` | Model inventory with real sizes from `MODELS.md`, doctor check, first-launch download (falls back to `bash scripts/download-models.sh`) |
| `PaywallView.swift` | 7-day trial, $12/mo or $99 lifetime, license-key activation (offline file), restore, honest Wispr/Superwhisper comparison, license blocker banner |
| `SettingsView.swift` | Cleanup model (0.6B / 1.7B), hotkey, paste target, beam size, camera index, model paths, custom words, personal LM (import-text / import-wispr / train-lm), reset |
| `OnboardingView.swift` | First launch: permissions (Camera, Input Monitoring, Accessibility) → model download → fast setup → trial |
| `Info.plist` | `LSUIElement` true, bundle id `com.subvox.local`, version 0.1.0, Camera usage description, macOS 14+ |
| `SubvoxLocal.entitlements` | Camera + outgoing network (model download only). Not sandboxed — the Python backend must run as a subprocess |

## How to build on the Intel Mac

```sh
# 1. Xcode 15+ (macOS 14 SDK), Swift 5.9+. Intel Mac, no Apple Silicon needed.
# 2. Create the Xcode project (or use swiftc directly for a first check):
cd ~/workspace/subvox-local/swift
xcodebuild -list   # after creating the project — see step 3

# 3. In Xcode: File → New → Project → macOS → App.
#    - Product name: SubvoxLocal
#    - Bundle id: com.subvox.local
#    - Interface: SwiftUI, Language: Swift
#    - Uncheck "Include Tests" for the first build (add them later).
#    Then drag all 11 .swift files in, replace the generated Info.plist
#    with this folder's Info.plist, and set the entitlements file to
#    SubvoxLocal.entitlements in Signing & Capabilities.
#    Set "Application is agent (UIElement)" — or keep LSUIElement in the plist.
#
# 4. Build: Cmd+B. Fix whatever the compiler complains about — the most
#    likely spots are listed under "Known risks" below.
#
# 5. Run: Cmd+R. Grant Camera when asked. Open the menu bar icon.
#
# 6. Backend: the app looks for the repo (setup_macos.sh) next to the
#    .app bundle, then at ~/workspace/subvox-local. Run ./setup_macos.sh
#    first so `uv run python -m subvox_local doctor` works from Terminal.
```

## What is NOT wired yet (gaps, not bugs to hide)

1. **Live dictation decode.** The Python CLI has no streaming dictation
   command. `DictationSession.startListening()` fails loudly with
   `dictationServeMissing` instead of faking a transcript. The Python side
   needs a JSON-lines mode (one object per hypothesis / cleaned / pasted
   event) before live hold-to-talk decode works. The `file` test path
   works today and is the way to verify decode on the Mac.
2. **Per-sentence recording from Swift.** `setup-fast` owns the record
   loop interactively (it prompts per sentence). The Setup view's
   per-sentence Record buttons start the full `setup-fast` run; true
   per-sentence control needs a non-interactive Python flag.
3. **In-app model download move.** `ModelDownloader` reports progress but
   the temp-file → final-path move is unfinished; the Download button runs
   the canonical `bash scripts/download-models.sh` instead. That script is
   resumable and is the reliable path.
4. **Qwen GGUF files.** The repo still ships MLX Qwen weights, which do
   not run on Intel. GGUF sizes and download URLs are marked TBD in
   `ModelsView` — pick the GGUF repo/file and paste the URL; do not guess.
5. **License key validation.** Any non-empty key is accepted and stored.
   Real validation (format / signature, offline or online) is TODO before
   any sale. The checkout URL is an empty placeholder.
6. **Right Option hotkey.** The `CGEventTap` is implemented but untested;
   if it fails, the app says so and Space/H still work. Input Monitoring
   permission must be granted in System Settings.
7. **Mouth-crop overlay position.** Estimated (lower-centre of frame)
   until live MediaPipe landmarks are wired in from the Python backend.
   The backend computes the real 96×96 crop; the overlay is a guide only.

## Known risks / Swift APIs to verify on macOS 14 + Intel

- `MenuBarExtra` with `.menuBarExtraStyle(.window)` — macOS 13+.
- `Layout` protocol (`FlowLayout` in SettingsView) — macOS 13+.
- `AVCaptureVideoPreviewLayer` inside `NSViewRepresentable` — verify the
  layer resizes with the view (`updateNSView` sets the frame).
- `CGEvent.tapCreate` for Right Option — needs Input Monitoring; verify
  the tap is created and that `flagsChanged` events do not double-fire.
- `NSEvent.addLocalMonitorForEvents` swallowing Space/H — verify it does
  not break typing in the paste-target field when not dictating (the
  monitor only swallows while the key is held for dictation; check this).
- `URLSessionDownloadDelegate` with resume (`Range` header) — verify the
  server honours it for Hugging Face resolve URLs.
- `Font.custom("Inter", ...)` falls back to system if Inter is not
  installed — verify the fallback looks right; GT America is not bundled.
- `LSUIElement = true` + `Window` scene — verify the main window opens
  from the menu bar on first launch (some LSUIElement apps need an
  explicit `openWindow` call; the menu bar does that here).
- `Process` launching `uv` — verify `uv` is on the PATH for a GUI app
  (GUI apps do not inherit the shell PATH; the app may need the full
  path to `uv`, e.g. `~/.local/bin/uv` or `~/.cargo/bin/uv`).

## License blocker (read before charging anyone)

The Auto-AVSR weights are LRS3, **non-commercial research only**
(see `LICENSES.md`). This app is fine for Francis's own use, but it
cannot be sold or charged for with these weights as-is. The paywall code
exists so the flow can be tested; turning it on commercially needs
replacement weights first. See CHARGING_PLAN (written by another agent).
The UI shows this banner on Dictate, Models, and Paywall — do not remove it.
