#!/usr/bin/env bash
# video-manage.sh — TUI for the whole video library.
#
# A gum-based terminal UI, styled by the active theme's palette: browse the
# library with live status, play any clip (video + palette), add a new clip
# (native file picker → Aether per-clip theme → mirrored into the library),
# and remove one (with confirmation). Long operations run behind a spinner.
# q/Esc or Quit exits.
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

# --- palette (themed by the active Omarchy theme via GUM_* env) --------------
ACC=${GUM_CHOOSE_CURSOR_FOREGROUND:-#26BBD9}
MUT=${GUM_FILE_FILE_SIZE_FOREGROUND:-#6F6F70}
TXT=${GUM_CHOOSE_ITEM_FOREGROUND:-#CBCED0}

# color <hex> <text> → ANSI-colored text
col() { printf '\033[38;2;%s%s\033[0m' "${1#*#}" "$2"; }

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

header() {
  local n_perclip=0
  local v
  for v in "${kind[@]:-}"; do
    if [[ $v == perclip ]]; then
      n_perclip=$((n_perclip + 1))
    fi
  done
  gum style \
    --border rounded \
    --border-foreground "$ACC" \
    --padding "0 2" \
    --foreground "$TXT" \
    "$(col "$ACC" "▸ video library")  ${#owner[@]} clips · $(col "$MUT" "$n_perclip per-clip") · theme: $(col "$ACC" "${CURRENT_THEME:-none}")"
}

feedback() {
  gum style --padding "0 1" --foreground "$TXT" "$1"
}

while :; do
  printf '\033[2J\033[H'   # clean screen each iteration

  labels=()
  for c in $(printf '%s\n' "${!owner[@]}" | sort); do
    tag=""
    [[ $c == "$CUR_BASE" ]] && tag="$(col "$ACC" '● playing')"
    case ${kind[$c]} in
      perclip) tag="$tag  $(col "$MUT" '[own palette]')" ;;
      lib)     tag="$tag  $(col "$MUT" '[library]')" ;;
    esac
    labels+=("$c$tag")
  done
  labels+=("$(col "$ACC" '+ Add a video…')")
  labels+=("$(col "$MUT" '⏻ Quit')")

  header
  echo ""
  choice="$(gum choose --header "" --cursor-prefix "❯ " --unselected-prefix "  " \
    "${labels[@]}")" || break
  echo ""

  if [[ $choice == *"⏻ Quit"* ]]; then
    break
  fi

  if [[ $choice == *"+ Add a video"* ]]; then
    # --- add -------------------------------------------------------------------
    start="$HOME"
    [[ -d $HOME/Videos ]] && start="$HOME/Videos"
    if file="$(gum file "$start")" && [[ -n $file ]]; then
      if gum spin --title "Adding '$(basename "$file")' — Aether palette…" \
           --show-output "$PLUGIN_BIN/video-add.sh" "$file"; then
        feedback "$(col "$ACC" '✓') added $(basename "$file")"
      else
        feedback "$(col "$MUT" '✗ add failed (see output above)')"
      fi
    fi
    current_state
    continue
  fi

  # the label is "<name>  <status…>"; names never contain double spaces
  c="${choice%%  *}"
  [[ -n ${owner[$c]:-} ]] || continue

  # --- action menu --------------------------------------------------------------
  action="$(gum choose --header "" \
    "$(col "$ACC" '▶ Play')" \
    "$(col "$MUT" '✕ Remove')" \
    "$(col "$MUT" '← Cancel')")" || continue
  echo ""
  case "$action" in
    *"▶ Play"*)
      t="${owner[$c]}"
      if [[ $t == "$CURRENT_THEME" ]]; then
        omarchy theme bg set "$USER_THEMES/$t/backgrounds/$c.png" >/dev/null 2>&1
      else
        omarchy theme set "$t" >/dev/null 2>&1
        omarchy theme bg set \
          "$HOME/.local/state/omarchy/current/theme/backgrounds/$c.png" >/dev/null 2>&1
      fi
      feedback "$(col "$ACC" '▶') playing $c $(col "$MUT" "($t)")"
      ;;
    *"✕ Remove"*)
      if gum confirm --affirmative "✕ Remove" --negative "✓ Keep" \
           "Remove '$c' from the library?"; then
        if gum spin --title "Removing '$c'…" --show-output \
             "$PLUGIN_BIN/video-remove.sh" "$c"; then
          feedback "$(col "$ACC" '✓') removed $c"
        else
          feedback "$(col "$MUT" '✗ remove failed (see output above)')"
        fi
      fi
      ;;
  esac
  current_state
done
