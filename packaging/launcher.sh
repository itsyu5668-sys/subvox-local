#!/usr/bin/env bash
# Subvox Local — backend launcher (lives in the .app bundle).
#   Subvox Local.app/Contents/Resources/launcher.sh [subvox-local args...]
#
# The Swift menu-bar app runs this on launch (its TODO socket bridge
# calls it; until that lands, run it by hand to test the backend).
# It does, in order:
#   1. Makes sure models exist in ~/Library/Application Support/Subvox Local/models/
#      — if the core models are missing, it starts the first-launch
#      downloader (stdlib python3, resumable) in the BACKGROUND and
#      returns immediately. It NEVER waits for the download: the old
#      version ran the downloader in the foreground, so the app window
#      could not open until ~1.62 GB had downloaded (10-30 min on slow
#      wifi) and the user saw a "downloading" popup and then nothing.
#      The Swift UI reads download-progress.json for the progress bar
#      and starts the same downloader itself on first launch; this
#      script is the fallback / hand-test path only.
#      Logs: ~/Library/Logs/SubvoxLocal/first-launch.log.
#   2. Symlinks <bundle>/Resources/subvox-backend/models -> the user
#      models dir, because src/subvox_local/paths.py resolves MODELS
#      from the bundle root (not from Application Support). No backend
#      code was changed for this; the symlink is the packaging fix.
#   3. Runs `subvox-local doctor` to verify the bundle is healthy.
#   4. Runs the backend with whatever arguments were passed
#      (no args = doctor only, then exit 0 — there is no daemon mode
#      yet; the Swift app invokes subcommands per action).
#
# UNTESTED ON INTEL MAC.
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/Subvox Local"
MODELS_DIR="$APP_SUPPORT/models"
LOG_DIR="$HOME/Library/Logs/SubvoxLocal"
PROGRESS_FILE="$APP_SUPPORT/download-progress.json"
BACKEND_DIR="$(cd "$(dirname "$0")/subvox-backend" && pwd)"
BACKEND="$BACKEND_DIR/subvox-local"
DOWNLOADER="$(cd "$(dirname "$0")" && pwd)/first_launch_downloader.py"

mkdir -p "$APP_SUPPORT" "$LOG_DIR"
exec >>"$LOG_DIR/launcher.log" 2>&1
echo "--- launcher $(date -u +%Y-%m-%dT%H:%M:%SZ) args: $*"

# 1. Models present? Core files the backend needs to start.
need_download=0
for f in vsr/model.pth vsr/model.json lm/model.pth lm/model.json \
         lm/unigram5000.model face_landmarker.task; do
  if [[ ! -s "$MODELS_DIR/$f" ]]; then need_download=1; break; fi
done

if [[ "$need_download" == "1" ]]; then
  echo "Core models missing — starting first-launch download (~1.62 GB) in the background."
  echo "Progress: $PROGRESS_FILE"
  echo "Log: $LOG_DIR/first-launch.log"
  # Already running? Do not start a second copy — re-running the app
  # while a download is in flight used to look like "nothing happens".
  # Check the PID file first; if that process is alive, just report it.
  PID_FILE="$APP_SUPPORT/download.pid"
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    echo "Download already running (PID $(cat "$PID_FILE")). Not starting a second copy."
    echo "Watch progress in the app's Models tab, or run: bash packaging/diagnose-first-launch.sh"
  else
    rm -f "$APP_SUPPORT/download.cancel" "$APP_SUPPORT/download.pause"
    nohup /usr/bin/python3 "$DOWNLOADER" --models-dir "$MODELS_DIR" \
        --progress-file "$PROGRESS_FILE" --include-qwen-gguf \
        >>"$LOG_DIR/first-launch.log" 2>&1 &
    echo $! > "$PID_FILE"
    echo "Download started in background (PID $(cat "$PID_FILE"))."
    echo "The app window opens now — training waits until the models land,"
    echo "but recording your sentences works while downloading."
  fi
fi

# 2. Symlink so paths.py (bundle-root-relative MODELS) finds them.
if [[ -L "$BACKEND_DIR/models" ]]; then
  rm "$BACKEND_DIR/models"
elif [[ -e "$BACKEND_DIR/models" ]]; then
  echo "WARNING: $BACKEND_DIR/models exists and is not a symlink — leaving it."
fi
if [[ ! -e "$BACKEND_DIR/models" ]]; then
  ln -s "$MODELS_DIR" "$BACKEND_DIR/models"
  echo "Linked $BACKEND_DIR/models -> $MODELS_DIR"
fi

# 3. Verify the frozen backend.
if [[ ! -x "$BACKEND" ]]; then
  echo "ERROR: backend binary missing: $BACKEND"
  echo "The .app was built without the PyInstaller backend. Re-run packaging/build_app.sh."
  exit 1
fi
"$BACKEND" doctor || {
  echo "ERROR: 'subvox-local doctor' failed — see log above."
  exit 1
}
echo "Backend healthy."

# 4. Run the requested subcommand, if any.
if [[ $# -gt 0 ]]; then
  exec "$BACKEND" "$@"
fi
echo "No subcommand given — backend is ready. The menu-bar app invokes subcommands."
exit 0
