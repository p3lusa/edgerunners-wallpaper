#!/usr/bin/env bash
# video-bg-picker.sh — unified wallpaper picker.
#
# Dispatcher for the unified wallpaper key (Super+Ctrl+Space). When the
# active theme ships a videos/ directory (a video theme) it opens the video
# switcher — the carousel of every clip in every video theme. Otherwise it
# falls back to the stock background picker, so image themes behave exactly
# as before.

set -euo pipefail

PLUGIN_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STAGED="${HOME}/.local/state/omarchy/current/theme"
if [[ -d "$STAGED/videos" ]] && ls "$STAGED/videos/"*.mp4 >/dev/null 2>&1; then
  exec "$PLUGIN_BIN/video-switcher.sh"
else
  exec omarchy-menu toggle background
fi
