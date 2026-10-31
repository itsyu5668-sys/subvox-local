#!/bin/bash
# Double-click this file to check why Subvox Local's first download is stuck.
# It runs packaging/diagnose-first-launch.sh and leaves the window open.
cd "$(dirname "$0")"
bash diagnose-first-launch.sh
echo
echo "Press Enter to close this window."
read -r
