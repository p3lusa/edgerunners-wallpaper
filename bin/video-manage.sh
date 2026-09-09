#!/usr/bin/env bash
# video-manage.sh — TUI for the whole video library.
#
# A gum-based terminal UI (styled by the active theme's palette): browse the
# library with live status, play any clip (switching video + palette), add a
# new clip (native file picker → Aether per-clip theme → mirrored into the
# library), and remove one (with confirmation). q/Esc quits.
#
# The same operations are available non-interactively:
#   video-add.sh <clip>      video-remove.sh <name>
#
# Usage:
#   video-manage.sh

set -euo pipefail

PLUGIN_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_THEMES="$HOME/.config/omarchy/themes"

# Self-deploy the usual wiring (idempotent, silent).
"$PLUGIN_BIN/video-bindings.sh" --add --quiet || true
"$PLUGIN_BIN/video-menu.sh" --add --quiet || true

# --- library scan (same set the switcher shows; per-clip themes win) ----------
declare -A owner=()   # clip base name -> theme that owns the entry
declare -A kind=()    # clip base name -> perclip | lib
declare -A theme_clips=()
for tdir in "$USER_THEMES"/*/; do
  [[ -d $tdir ]] || continue
  [[ -d "$tdir/backgrounds" && -d "$tdir/videos" ]] || continue
  t="${tdir%/}"; t="${t##*/}"
  clips=()
  for poster in "$tdir"/backgrounds/*; do
    [[ -f $poster ]] || continue
    b="${poster##*/}"; b="${b%.*}"
    [[ -f "$tdir/videos/$b.mp4" ]] || continue
    clips+=("$b")
  done
  if (( ${#clips[@]} > 0 )); then
    theme_clips["$t"]="${clips[*]}"
  fi
done
for tdir in "$USER_THEMES"/*/; do
  [[ -f "${tdir}.video-theme" ]] || continue
  t="${tdir%/}"; t="${t##*/}"
  for c in ${theme_clips[$t]:-}; do
    owner["$c"]="$t"
    kind["$c"]="perclip"
  done
done
for t in "${!theme_clips[@]}"; do
  [[ -f "$USER_THEMES/$t/.video-theme" ]] && continue
  for c in ${theme_clips[$t]}; do
    [[ -n ${owner[$c]:-} ]] && continue
    owner["$c"]="$t"
    kind["$c"]="lib"
  done
done

current_state() {
  CURRENT_THEME="$(tr -d '[:space:]' < "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)"
  CURRENT_BG="$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)"
  CUR_BASE=""
  if [[ -n $CURRENT_BG ]]; then
    CUR_BASE="${CURRENT_BG##*/}"
    CUR_BASE="${CUR_BASE%.*}"
  fi
}
current_state

while :; do
  labels=()
  for c in $(printf '%s\n' "${!owner[@]}" | sort); do
    tag=""
    [[ $c == "$CUR_BASE" ]] && tag="  ● playing"
    case ${kind[$c]} in
      perclip) tag="${tag}  [own palette]" ;;
      lib)     tag="${tag}  [library]" ;;
    esac
    labels+=("$c$tag")
  done
  labels+=("+ Add a video…")
  labels+=("Quit")

  choice="$(gum choose "${labels[@]}")" || break

  if [[ $choice == "Quit" ]]; then
    break
  fi
  if [[ $choice == "+ "* ]]; then
    # --- add -------------------------------------------------------------------
    start="$HOME"
    [[ -d $HOME/Videos ]] && start="$HOME/Videos"
    if file="$(gum file "$start")" && [[ -n $file ]]; then
      "$PLUGIN_BIN/video-add.sh" "$file" || true
    fi
    current_state
    continue
  fi

  # the label is "<name>  <status…>"; names never contain double spaces
  c="${choice%%  *}"
  [[ -n ${owner[$c]:-} ]] || continue

  # --- action menu --------------------------------------------------------------
  action="$(gum choose "Play" "Remove" "Cancel")" || continue
  case "$action" in
    Play)
      t="${owner[$c]}"
      if [[ $t == "$CURRENT_THEME" ]]; then
        omarchy theme bg set "$USER_THEMES/$t/backgrounds/$c.png" >/dev/null 2>&1
      else
        omarchy theme set "$t" >/dev/null 2>&1
        omarchy theme bg set \
          "$HOME/.local/state/omarchy/current/theme/backgrounds/$c.png" >/dev/null 2>&1
      fi
      ;;
    Remove)
      if gum confirm --yes-text "Remove" --no-text "Keep" \
           "Remove '$c' from the library?"; then
        "$PLUGIN_BIN/video-remove.sh" "$c" || true
      fi
      ;;
  esac
  current_state
done
