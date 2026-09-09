#!/usr/bin/env bash
# video-cleanup.sh — reap abandoned per-clip video themes.
#
# Every theme created by video-theme.sh carries a .video-theme marker. A
# marked theme is kept while it is the active theme or registered in the
# cycle list (~/.config/omarchy/video-themes). Anything else is considered
# abandoned and is removed, so it stops appearing in the stock theme
# selector (Omarchy lists every theme in ~/.config/omarchy/themes and has
# no hidden-theme mechanism). Stale cycle-list entries (themes that no
# longer exist) are pruned as well.
#
# Unmarked themes — including the multi-clip library theme (video-wallpaper)
# and every normal theme — are never touched.
#
# Silent by design: the video tools run it on every invocation.

set -euo pipefail

USER_THEMES="$HOME/.config/omarchy/themes"
list="$HOME/.config/omarchy/video-themes"
CURRENT_THEME="$(tr -d '[:space:]' < "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || echo "")"

# Keep set: the active theme + every theme in the cycle list.
declare -A keep=()
if [[ -n $CURRENT_THEME ]]; then
  keep["$CURRENT_THEME"]=1
fi
if [[ -f $list ]]; then
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"   # ltrim
    line="${line%"${line##*[![:space:]]}"}"   # rtrim
    if [[ -n $line ]]; then
      keep["$line"]=1
    fi
  done <"$list"
fi

# Reap: marked themes that are neither active nor registered.
for marker in "$USER_THEMES"/*/.video-theme; do
  if [[ ! -e $marker ]]; then
    continue
  fi
  t="${marker%/*}"; t="${t##*/}"
  if [[ -z ${keep[$t]:-} ]]; then
    omarchy theme remove "$t" >/dev/null 2>&1 || rm -rf "$USER_THEMES/$t"
  fi
done

# Prune cycle-list entries whose theme no longer exists.
if [[ -f $list ]]; then
  tmp="$(mktemp)"
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"   # ltrim
    line="${line%"${line##*[![:space:]]}"}"   # rtrim
    if [[ -n $line && -d "$USER_THEMES/$line" ]]; then
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$list"
  mv "$tmp" "$list"
fi
