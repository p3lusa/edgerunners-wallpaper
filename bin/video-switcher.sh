#!/bin/bash
# p3lu.video-background: carousel selector for the video themes.
#
# Same UI as Omarchy's wallpaper switcher (a wrapper around
# omarchy-menu-images), but each entry is a complete video theme: its poster
# is the preview, and selecting it runs `omarchy theme set`, switching video,
# background, and palette together.
#
# Entries come from the cycle list (~/.config/omarchy/video-themes, maintained
# by video-theme.sh); when the list is absent it falls back to every
# video-* theme in ~/.config/omarchy/themes.

set -euo pipefail

PLUGIN_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Self-deploy the keybindings (idempotent, silent, no reload if unchanged).
"$PLUGIN_BIN/video-bindings.sh" --add --quiet

CYCLE_LIST="$HOME/.config/omarchy/video-themes"
USER_THEMES="$HOME/.config/omarchy/themes"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/video-switcher"
CURRENT_THEME="$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)"

themes=()
if [[ -f $CYCLE_LIST ]]; then
  while IFS= read -r t; do
    t="${t%%$'\r'}"
    [[ -n $t && $t != \#* ]] && themes+=("$t")
  done <"$CYCLE_LIST"
fi
if (( ${#themes[@]} == 0 )); then
  for d in "$USER_THEMES"/video-*; do
    [[ -d $d ]] && themes+=("$(basename "$d")")
  done
fi
(( ${#themes[@]} > 0 )) || exit 0

# Rebuild the poster cache: <theme>.<ext> -> the theme's first background.
rm -rf "$CACHE_DIR"
mkdir -p "$CACHE_DIR"
for t in "${themes[@]}"; do
  poster=$(find -L "$USER_THEMES/$t/backgrounds" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \) \
    -print 2>/dev/null | sort | head -n1)
  [[ -n $poster ]] && ln -s "$poster" "$CACHE_DIR/$t.${poster##*.}"
done
(( $(find "$CACHE_DIR" -type l | wc -l) > 0 )) || exit 0

# Preselect the current theme's poster when it is one of the entries.
selected_flag=()
for f in "$CACHE_DIR/$CURRENT_THEME".*; do
  if [[ -e $f ]]; then
    selected_flag=(--selected "$f")
    break
  fi
done

name=$(omarchy-menu-images --print-name ${selected_flag[@]+"${selected_flag[@]}"} "$CACHE_DIR" || true)
[[ -n ${name:-} ]] || exit 0

omarchy theme set "$name"
