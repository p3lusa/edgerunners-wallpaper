#!/usr/bin/env bash
# video-cycle.sh — switch to the next (or previous) video theme.
#
# Each clip created with video-theme.sh is its own theme (own palette via
# Aether, own video). This walks the ordered cycle list that the helper
# maintains and activates the adjacent theme: `omarchy theme set` does the
# rest (re-stage, animated palette + background transition, video follows).
#
# Usage:
#   video-cycle.sh next
#   video-cycle.sh prev
#
# The wrappers video-next.sh / video-prev.sh call this script.
#
# List file: ~/.config/omarchy/video-themes (one theme name per line, in
# cycle order). If the currently active theme is not in the list, the cycle
# starts at its first entry.

set -euo pipefail

# Self-deploy the video keybindings (idempotent, silent; no-op when already
# present, so no Hyprland reload storms).
"$(dirname "${BASH_SOURCE[0]}")/video-bindings.sh" --add --quiet || true

if [[ $# -ne 1 || ( "$1" != "next" && "$1" != "prev" ) ]]; then
  echo "Usage: $(basename "$0") <next|prev>" >&2
  exit 2
fi
direction="$1"

list="${HOME}/.config/omarchy/video-themes"
if [[ ! -f "$list" ]]; then
  echo "error: no video themes registered." >&2
  echo "       create one first: video-theme.sh <clip.mp4> [theme-name]" >&2
  exit 1
fi

themes=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"   # ltrim
  line="${line%"${line##*[![:space:]]}"}"   # rtrim
  [[ -n "$line" ]] && themes+=("$line")
done < "$list"

n=${#themes[@]}
if (( n == 0 )); then
  echo "error: the video-theme list is empty: $list" >&2
  exit 1
fi

# The active theme name is recorded by Omarchy in current/theme.name (the
# staged theme directory itself is a generic copy).
current="$(tr -d '[:space:]' < "${HOME}/.local/state/omarchy/current/theme.name" 2>/dev/null || echo "")"

idx=-1
for i in "${!themes[@]}"; do
  if [[ "${themes[$i]}" == "$current" ]]; then
    idx=$i
    break
  fi
done

if [[ "$direction" == "next" ]]; then
  if (( idx == -1 )); then
    next_idx=0
  else
    next_idx=$(( (idx + 1) % n ))
  fi
else
  if (( idx == -1 )); then
    next_idx=0
  else
    next_idx=$(( (idx - 1 + n) % n ))
  fi
fi

next="${themes[$next_idx]}"

if [[ "$next" == "$current" ]] && (( n == 1 )); then
  echo "only one video theme registered: $next (already active)"
  exit 0
fi

if ! omarchy theme set "$next" >/dev/null 2>&1; then
  echo "error: omarchy theme set $next failed" >&2
  exit 1
fi
echo "video theme: $next"
