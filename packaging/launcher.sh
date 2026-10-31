#!/usr/bin/env bash
# Subvox Local — backend launcher (lives in the .app bundle).
#   Subvox Local.app/Contents/Resources/launcher.sh [subvox-local args...]
#
# The Swift menu-bar app runs this on launch (its TODO socket bridge
# calls it; until that lands, run it by hand to test the backend).
# It does, in order:
#   1. Makes sure models exist in ~/Library/Application Support/Subvox Local/models/
#      — if the core models are missing, it starts the first-launch
#      downloader (stdlib python3, resumable) in the background and waits
#      for it, logging to ~/Library/Logs/SubvoxLocal/first-launch.log.
#      The Swift UI reads download-progress.json for the progress bar.
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
  echo "Core models missing — starting first-launch download (~1.22 GB)."
  echo "Progress: $PROGRESS_FILE"
  # --include-qwen-gguf prints the no-URL-yet warning; it is harmless
  # and keeps the gap visible in the log until a GGUF file is chosen.
  dl_status=0
  /usr/bin/python3 "$DOWNLOADER" --models-dir "$MODELS_DIR" \
      --progress-file "$PROGRESS_FILE" --include-qwen-gguf || dl_status=$?
  if [[ "$dl_status" -ne 0 ]]; then
    echo "ERROR: model download exited $dl_status (2 = cancelled, 1 = failed)."
    echo "Re-run this launcher (or the downloader directly) to resume — completed files are kept."
    exit "$dl_status"
  fi
  echo "Model download finished; verifying…"
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
