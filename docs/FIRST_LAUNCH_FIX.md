# First-launch download fix — 2026-10-31

Francis opened the run 11 .dmg app, saw a "downloading" popup, then
nothing happened, and re-opening the app did nothing. This is the fix.

## Root cause (three bugs, not one)

1. **The download never started, and the button locked itself.**
   `AppState.beginBackgroundDownload()` ran
   `python3 packaging/first_launch_downloader.py` with a relative path,
   from a repo root found by looking for a `subvox-local` folder next to
   the .app or in `~/workspace/subvox-local`. Neither exists on a real
   user's Mac (the app lives in /Applications, alone). So it returned
   silently — but it had already set `backgroundDownloadStarted = true`,
   so the button changed to "Download running in background", disabled,
   with nothing downloading. No error, no retry, dead end.

2. **Re-opening a running app showed nothing.** The app was
   `LSUIElement` (menu-bar only, no Dock icon). Double-clicking the .app
   while it was already running just activates the existing process. With
   the main window closed, there was nothing visible to click — only a
   tiny ✳ in the menu bar. That is exactly "I try to open it again,
   nothing".

3. **A stalled / failed download froze the progress bar forever.**
   The downloader crashed on network errors (wifi drop, Hugging Face
   timeout) with a traceback, leaving the progress JSON stuck on
   `"downloading"` at a frozen percent. The Swift monitor never checked
   whether the file was going stale, so the UI showed the same number
   forever. And `packaging/launcher.sh` ran the downloader in the
   foreground, so if it was ever invoked, the app window could not open
   until ~1.62 GB had finished.

## What changed

- `swift/AppState.swift` — the downloader is now resolved from the .app
  bundle first (`Contents/Resources/first_launch_downloader.py`, which
  `build_app.sh` already copies in), repo second, and never from a
  relative path alone. `backgroundDownloadStarted` is set only AFTER
  the process actually launches. Failures set a plain-English
  `downloadError` shown in the UI, reset the flag so Retry works, and
  the process exit code is checked. New: `retryBackgroundDownload()`,
  `retryAfterStall()` (max 2 auto-retries), `coreModelsPresent()`, and
  `autoStartDownloadIfNeeded()` — first launch starts the download
  immediately and opens the Models tab, so the user sees a big visible
  progress window the moment the app opens.
- `swift/DownloadProgress.swift` — decodes the downloader's `updated`
  timestamp and `error_message`. Stall detection: status "downloading"
  but no new bytes for 60 seconds → `isStalled`, the card says so in
  plain English, and AppState auto-retries. Error status shows the
  reason. The card now has a Retry button.
- `swift/SubvoxLocalApp.swift` — `SubvoxAppDelegate` brings the main
  window to the front on activate and on reopen; `ContentView` also
  re-opens the main window on `didBecomeActive` and auto-starts the
  download on appear.
- `packaging/Info.plist` and `swift/Info.plist` — `LSUIElement` is now
  `false`: the app has a Dock icon (menu-bar ✳ stays). Clicking the
  Dock icon always brings the window forward.
- `packaging/first_launch_downloader.py` — network errors are caught
  per file, written to the progress JSON as status `"error"` with a
  plain-English `error_message`, retried once after 5 seconds, and only
  then fail. An unexpected exception also writes `"error"` instead of
  dying with a stale `"downloading"` file.
- `packaging/launcher.sh` — the downloader now starts in the background
  (`nohup … &`, PID file) and the script returns immediately. It refuses
  to start a second copy if one is already running.
- `packaging/diagnose-first-launch.sh` + `.command` (new, copied into
  the .app by `build_app.sh`) — double-clickable diagnosis in plain
  English: is the app running, progress percent / MB / speed / ETA,
  which core files are present or missing, `.part` files, pause/cancel
  flags, last log lines, and a one-line verdict.
- `swift/OnboardingView.swift`, `swift/ModelsView.swift` — progress
  cards wired to Retry; error text shown in the UI.

## 3 checks Francis can do on his Mac (no Terminal)

1. **Click the Subvox icon in the Dock.** The window must come to the
   front every time — that is the re-open fix. If there is no Dock icon,
   he has the old .dmg; download the new one.
2. **Open the Models tab.** It must show a big progress bar with
   "X MB of 1,618 MB — N%", a speed, and a time left — not a frozen
   number. If it says "looks stuck" or shows an error, tap Retry.
3. **Double-click `diagnose-first-launch.command`** (inside the .app at
   Contents/Resources, or from the repo's packaging/ folder). It prints
   a verdict: downloading / stuck / finished / never started.

## Still untested on a real Mac

Swift was never compiled here (Linux VM, no Xcode/swiftc). The new
Swift code is syntactically reviewed only — brace balance checked,
no new APIs beyond Foundation/SwiftUI/AppKit already in use. The first
green GitHub Actions run compiles it; if swiftc fails, fix the Swift
there, do not work around it. The download itself (1.62 GB, Hugging
Face + GitHub + Google hosts) has not been run end to end on Francis's
wifi — stall detection and resume are the safety net, not a proof.
