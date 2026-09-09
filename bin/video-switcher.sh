#!/bin/bash
# p3lu.video-background: carousel selector for all available videos.
#
# Same UI as Omarchy's wallpaper switcher (a wrapper around
# omarchy-menu-images). Entries:
#   - the current theme's own clips (poster previews; the clip is the
#     background's paired video) — selecting one runs
#     `omarchy theme bg set`, staying in the same theme/palette;
#   - the per-clip video themes (the cycle list maintained by
#     video-theme.sh, falling back to every video-* theme) — selecting one
#     runs `omarchy theme set`, switching video + palette together.
# The current video is preselected.

set -euo pipefail

PLUGIN_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Self-deploy the keybindings (idempotent, silent, no reload if unchanged).
"$PLUGIN_BIN/video-bindings.sh" --add --quiet || true

CYCLE_LIST="$HOME/.config/omarchy/video-themes"
USER_THEMES="$HOME/.config/omarchy/themes"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/video-switcher"
CURRENT_THEME="$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)"
CURRENT_THEME_PATH="$HOME/.local/state/omarchy/current/theme"
CURRENT_BACKGROUND="$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)"

rm -rf "$CACHE_DIR"
mkdir -p "$CACHE_DIR"

# --- the current theme's clips (poster + paired video) ---------------------
# clip_real[name] = real poster path for every entry added
declare -A clip_real=()
if [[ -n $CURRENT_THEME && -d $CURRENT_THEME_PATH ]]; then
  for poster in "$CURRENT_THEME_PATH"/backgrounds/*; do
    [[ -f $poster ]] || continue
    base="${poster##*/}"; base="${base%.*}"
    # only entries with a paired video belong in a *video* selector
    [[ -f "$CURRENT_THEME_PATH/videos/$base.mp4" ]] || continue
    ln -s "$poster" "$CACHE_DIR/$base.${poster##*.}"
    clip_real["$base"]="$poster"
  done
fi

# --- the per-clip video themes ---------------------------------------------
# theme_names: every entry that is a theme, not a clip of the current theme
theme_names=()
declare -A theme_seen=()
add_theme() {
  local t="$1"
  [[ -n $t && -z ${theme_seen[$t]:-} && -d "$USER_THEMES/$t" ]] || return 0
  # skip a theme whose name collides with a clip of the current theme
  [[ -n ${clip_real[$t]:-} ]] && return 0
  theme_seen["$t"]=1
  theme_names+=("$t")
  local poster
  poster=$(find -L "$USER_THEMES/$t/backgrounds" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \) \
    -print 2>/dev/null | sort | head -n1)
  [[ -n $poster ]] && ln -s "$poster" "$CACHE_DIR/$t.${poster##*.}"
}

if [[ -f $CYCLE_LIST ]]; then
  while IFS= read -r t; do
    t="${t%%$'\r'}"
    [[ -n $t && $t != \#* ]] && add_theme "$t"
  done <"$CYCLE_LIST"
fi
if (( ${#theme_names[@]} == 0 )); then
  for d in "$USER_THEMES"/video-*; do
    [[ -d $d ]] && add_theme "$(basename "$d")"
  done
fi

(( $(find "$CACHE_DIR" -type l | wc -l) > 0 )) || exit 0

# --- preselect the current video --------------------------------------------
selected_flag=()
if [[ -n $CURRENT_BACKGROUND ]]; then
  cur_base="${CURRENT_BACKGROUND##*/}"; cur_base="${cur_base%.*}"
  if [[ -e "$CACHE_DIR/$cur_base".* ]] || [[ -n ${theme_seen[$CURRENT_THEME]:-} ]]; then
    for f in "$CACHE_DIR/$cur_base".* "$CACHE_DIR/$CURRENT_THEME".*; do
      if [[ -e $f ]]; then
        selected_flag=(--selected "$f")
        break
      fi
    done
  fi
fi

name=$(omarchy-menu-images --print-name ${selected_flag[@]+"${selected_flag[@]}"} "$CACHE_DIR" || true)
[[ -n ${name:-} ]] || exit 0

# --- dispatch: clip of the current theme, or a per-clip video theme ---------
if [[ -n ${clip_real[$name]:-} ]]; then
  omarchy theme bg set "${clip_real[$name]}"
else
  omarchy theme set "$name"
fi
