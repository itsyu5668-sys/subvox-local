#!/usr/bin/env bash
# Subvox Local — first-launch download diagnosis (Intel Mac).
#
# Double-click diagnose-first-launch.command (next to this file, or
# inside the .app at Contents/Resources/) and it runs this script and
# prints, in plain English:
#   - is Subvox Local running right now
#   - what the download progress file says (percent, MB, speed, ETA,
#     last update time, and any error message)
#   - which model files are present / missing, and how big the models
#     folder is so far
#   - whether a half-downloaded .part file exists (that is normal —
#     it means the download can resume instead of starting over)
#   - the last 20 lines of the download log
#   - a one-line verdict: downloading / stuck / finished / never started
#
# No Terminal knowledge needed: the .command file opens Terminal,
# runs this, and leaves the window open. Copy the whole output and
# send it to whoever is helping you.
set -u

APP_SUPPORT="$HOME/Library/Application Support/Subvox Local"
MODELS_DIR="$APP_SUPPORT/models"
PROGRESS_FILE="$APP_SUPPORT/download-progress.json"
LOG_DIR="$HOME/Library/Logs/SubvoxLocal"
FIRST_LOG="$LOG_DIR/first-launch.log"
LAUNCHER_LOG="$LOG_DIR/launcher.log"

echo "=============================================="
echo " Subvox Local — first-launch download check"
echo "=============================================="
echo

echo "--- Is the app running? ---"
if pgrep -x "SubvoxLocal" >/dev/null 2>&1; then
  echo "YES — Subvox Local is running (process: $(pgrep -x SubvoxLocal | tr '\n' ' '))"
  echo "If you cannot see its window, click its icon in the Dock, or click the ✳ in the menu bar, then 'Open main window'."
else
  echo "NO — Subvox Local is not running."
  echo "Open it from Applications. If it opens and nothing appears, the window may be hidden — check the Dock."
fi
echo

echo "--- Download progress ---"
if [[ -f "$PROGRESS_FILE" ]]; then
  /usr/bin/python3 - "$PROGRESS_FILE" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"Progress file exists but cannot be read: {e}")
    sys.exit(0)
total = d.get("overall_total_bytes") or 0
done = d.get("overall_downloaded_bytes") or 0
print(f"Status: {d.get('status')}")
print(f"Downloaded: {done/1e6:.1f} MB of {total/1e6:.1f} MB ({d.get('overall_percent')}% )")
print(f"Current file: {d.get('current_file')}")
print(f"Speed: {(d.get('bytes_per_sec') or 0)/1e6:.1f} MB/s")
eta = d.get("overall_eta_seconds")
print(f"Time left: {eta} seconds" if eta is not None else "Time left: still working it out")
print(f"Models done: {d.get('models_done')} of {d.get('models_total')}")
print(f"Last update: {d.get('updated')}")
if d.get("error_message"):
    print(f"Error: {d.get('error_message')}")
PYEOF
else
  echo "No progress file yet — the download has NEVER started."
  echo "That means the app opened but the downloader never ran."
  echo "Open the app, go to the Models tab, and tap 'Start download'."
fi
echo

echo "--- Model files (core set, about 1.62 GB total) ---"
if [[ -d "$MODELS_DIR" ]]; then
  echo "Models folder size so far: $(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1)"
else
  echo "Models folder does not exist yet — nothing has downloaded."
fi
for f in vsr/model.pth vsr/model.json lm/model.pth lm/model.json lm/unigram5000.model face_landmarker.task qwen3-0.6b-gguf/Qwen3-0.6B-Q4_K_M.gguf; do
  if [[ -s "$MODELS_DIR/$f" ]]; then
    echo "  OK      $f ($(du -h "$MODELS_DIR/$f" | cut -f1))"
  else
    echo "  MISSING $f"
  fi
done
echo
echo "--- Half-downloaded files (.part = can resume, this is normal) ---"
if find "$MODELS_DIR" -name "*.part" 2>/dev/null | grep -q .; then
  find "$MODELS_DIR" -name "*.part" -exec du -h {} \; 2>/dev/null
else
  echo "None."
fi
echo

echo "--- Pause / cancel flags ---"
[[ -f "$APP_SUPPORT/download.pause" ]] && echo "PAUSED — a pause file exists. Tap Resume in the app." || echo "Not paused."
[[ -f "$APP_SUPPORT/download.cancel" ]] && echo "CANCELLED — a cancel file exists. Re-open the app to resume." || echo "Not cancelled."
echo

echo "--- Last 20 lines of the download log ---"
if [[ -f "$FIRST_LOG" ]]; then
  tail -20 "$FIRST_LOG"
else
  echo "No download log yet ($FIRST_LOG does not exist)."
fi
echo
echo "--- Last 10 lines of the launcher log ---"
if [[ -f "$LAUNCHER_LOG" ]]; then
  tail -10 "$LAUNCHER_LOG"
else
  echo "No launcher log yet."
fi
echo

echo "=============================================="
echo " VERDICT"
echo "=============================================="
if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "Download never started. Open the app, go to Models, tap Start download."
elif /usr/bin/python3 -c "import json,sys; d=json.load(open('$PROGRESS_FILE')); sys.exit(0 if d.get('status')=='done' else 1)" 2>/dev/null; then
  echo "Download FINISHED. If the app still does nothing, the problem is not the download — send this whole output to support."
elif pgrep -f "first_launch_downloader" >/dev/null 2>&1; then
  echo "Download is RUNNING right now. It downloads about 1.62 GB, which takes a while. Leave the app open and watch the Models tab."
else
  echo "Download is NOT running, and it is not finished. It probably stalled or failed."
  echo "Re-open the app and tap Retry download in the Models tab. It resumes from where it stopped."
fi
echo
echo "Done. You can close this window."
