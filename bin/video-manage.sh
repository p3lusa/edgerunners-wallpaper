#!/usr/bin/env bash
# video-manage — video library manager (TUI).
#
# Stack (Charm best practice for shell TUIs, zero extra deps on an
# Omarchy system):
#   fzf  — list engine: fuzzy filter, preview pane, themed border,
#          custom keys
#   gum  — modals: file picker, confirm, spinner (themed by the active
#          palette via GUM_* env vars)
#
# Keys: Enter play · r remove · a add · ? help · q/Esc quit
set -euo pipefail

# ---------------------------------------------------------------- paths ----
PLUGIN_BIN="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
THEMES_USER="$HOME/.config/omarchy/themes"
THEMES_SYS="${OMARCHY_PATH:-/usr/share/omarchy}/themes"
STAGED_BG_LINK="$HOME/.local/state/omarchy/current/background"
LIB_THEME="video-wallpaper"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/video-manage"
META_DIR="$CACHE_ROOT/meta"
mkdir -p "$META_DIR"
SESSION="$(mktemp -d "$CACHE_ROOT/session.XXXXXX")"
trap 'rm -rf "$SESSION"' EXIT

# --------------------------------------------------------------- helpers ----
# col <hex> <text> — truecolor SGR (hex may include #)
col() { local h=${1##'#'}; shift
  [[ ${#h} -eq 6 ]] || { printf '%s' "$*"; return; }
  printf '\033[38;2;%d;%d;%dm%s\033[0m' \
    $((16#${h:0:2})) $((16#${h:2:2})) $((16#${h:4:2})) "$*"
}
# strip ANSI escapes from stdin
strip_ansi() { sed -e 's/\x1b\[[0-9;]*m//g'; }
export -f col strip_ansi

# Palette of the *currently staged* theme. Re-read every loop iteration so
# the TUI re-themes itself when a per-clip palette is applied.
load_palette() {
  local cf="$HOME/.local/state/omarchy/current/theme/colors.toml"
  ACC="#5FB3FF" TXT="#E4E4E4" BG="#1C1E26" MUT="#959DA5"
  [[ -f $cf ]] || return 0
  local v
  v=$(sed -n 's/^accent[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$cf" | head -1)
  [[ -n $v ]] && ACC="$v"
  v=$(sed -n 's/^foreground[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$cf" | head -1)
  [[ -n $v ]] && TXT="$v"
  v=$(sed -n 's/^background[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$cf" | head -1)
  [[ -n $v ]] && BG="$v"
  v=$(sed -n 's/^color8[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$cf" | head -1)
  [[ -n $v ]] && MUT="$v"
  export ACC TXT BG MUT
}

# Icons: Nerd Font codepoints when the system has a Nerd Font (Omarchy's
# default), ASCII fallback otherwise.
declare_icons() {
  # no grep -q: pipefail + SIGPIPE haría fallar la condición
  if command -v fc-list >/dev/null 2>&1 && [[ -n $(fc-list 2>/dev/null | grep -i nerd) ]]; then
    I_ADD=$'\uf067' I_RM=$'\uf1f8' I_HELP=$'\uf059' I_DOT=$'\uf111'
    I_FILM=$'\uf008'
  else
    I_ADD='+' I_RM='x' I_HELP='?' I_DOT='*' I_FILM='>'
  fi
  export I_ADD I_RM I_HELP I_DOT I_FILM
}

# ---------------------------------------------------------------- library ----
# $SESSION/library.tsv: name \t theme \t file \t kind(own|lib)
# Dedup: per-clip themes (with .video-theme marker) claim their clips;
# library themes drop clips already claimed.
scan_library() {
  local tmp="$SESSION/scan.tmp"
  : > "$tmp"
  local t b perclip f base
  local -A claimed=()
  for t in "$THEMES_USER"/* "$THEMES_SYS"/*; do
    [[ -d $t && -d $t/videos && -d $t/backgrounds ]] || continue
    b=$(basename "$t")
    perclip=0
    [[ -f $t/.video-theme ]] && perclip=1
    for f in "$t"/videos/*.mp4; do
      [[ -e $f ]] || continue
      base=$(basename "$f" .mp4)
      if [[ $perclip == 1 ]]; then
        printf '%s\t%s\t%s\t%s\n' "$base" "$b" "$f" own >> "$tmp"
        claimed["$base"]=1
      elif [[ -z ${claimed["$base"]:-} ]]; then
        printf '%s\t%s\t%s\t%s\n' "$base" "$b" "$f" lib >> "$tmp"
      fi
    done
  done
  local tab; tab=$(printf '\t')
  sort -t"$tab" -k1,1 -o "$SESSION/library.tsv" "$tmp"
  rm -f "$tmp"
}

current_state() {
  # same sources of truth as video-cycle.sh
  CUR_THEME=$(tr -d '[:space:]' < "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null) || CUR_THEME=""
  CUR_THEME=${CUR_THEME:-?}
  CUR_BASE=""
  local bg
  bg=$(readlink -f "$STAGED_BG_LINK" 2>/dev/null) || bg=""
  if [[ -n $bg ]]; then
    CUR_BASE="${bg##*/}"
    CUR_BASE="${CUR_BASE%.*}"
  fi
  export CUR_THEME CUR_BASE
}

# ffprobe metadata, cached per clip (invalidated by mtime).
clip_meta() { # <file> → "20s · 1920x1080@30fps · 12.3 MB"
  local file=$1 m="$META_DIR/$(basename "$file" .mp4).meta"
  if [[ ! -f $m || $file -nt $m ]]; then
    local out w h rate dur size fps dur_s size_mb
    out=$(ffprobe -v error -select_streams v:0 \
      -show_entries stream=width,height,avg_frame_rate:format=duration,size \
      -of csv=p=0 "$file" 2>/dev/null) || out=""
    out=${out//$'\n'/,}
    IFS=',' read -r w h rate dur size <<<"$out"
    fps=${rate%%/*}
    dur_s=${dur%%.*}
    size_mb=$(awk -v s="${size:-0}" 'BEGIN{printf "%.1f", s/1048576}')
    printf '%ss · %sx%s@%sfps · %s MB\n' \
      "${dur_s:-?}" "${w:-?}" "${h:-?}" "${fps:-?}" "${size_mb:-?}" > "$m"
  fi
  cat "$m" 2>/dev/null || true
}
export -f clip_meta
export META_DIR

# ------------------------------------------------------------- list/preview ----
# clip line format:  "MARK NAME  [tag]"   (MARK = ● or two spaces)
line_to_name() {
  sed -E 's/^.{2}//; s/  \[[^]]*\]$//' <<<"$1"
}
export -f line_to_name
export SESSION

tag_for() { [[ $1 == own ]] && echo "own palette" || echo "library"; }

render_clip() { # <name> <theme> <kind>
  local name=$1 theme=$2 kind=$3 tag
  tag=$(tag_for "$kind")
  if [[ $name == "$CUR_BASE" && $theme == "$CUR_THEME" ]]; then
    printf '%s %s %s\n' \
      "$(col "$ACC" "$I_DOT ")" "$(col "$ACC" "$name")" \
      "$(col "$MUT" "[$tag]")"
  else
    printf '%s %s %s\n' \
      "$(col "$MUT" "  ")" "$(col "$TXT" "$name")" \
      "$(col "$MUT" "[$tag]")"
  fi
}
export -f render_clip tag_for

build_list() {
  local name theme file kind
  {
    printf '%s %s\n' "$(col "$ACC" "$I_ADD  ")" "Add a video"
    printf '%s %s\n' "$(col "$MUT" "$I_RM   ")" "Remove a video"
    printf '%s %s\n' "$(col "$MUT" "$I_HELP ")" "How to use"
    while IFS=$'\t' read -r name theme file kind; do
      render_clip "$name" "$theme" "$kind"
    done < "$SESSION/library.tsv"
  }
}

build_clips_only() {
  local name theme file kind
  while IFS=$'\t' read -r name theme file kind; do
    render_clip "$name" "$theme" "$kind"
  done < "$SESSION/library.tsv"
}

# preview pane (right 1/3). Also records the highlighted line in $SESSION/hl
# (state hook for the 'r' key).
preview_cmd() {
  local line plain name row theme file kind status rule
  line=$1
  plain=$(strip_ansi <<<"$line")
  printf '%s' "$plain" > "$SESSION/hl"
  rule="────────────────────────────────────────"
  case $plain in
    *"Add a video"*)
      printf '%s\n' "Add a video" "$rule" "" \
        "Pick a clip (mp4/mov/webm). If it carries an audio track" \
        "you are asked to drop it (lossless remux — the plugin has" \
        "no volume control). Its palette is then extracted with" \
        "Aether, a per-clip theme is created, and the clip is" \
        "mirrored into the library theme (hardlinks — zero extra" \
        "space). Adding never changes the current wallpaper —" \
        "press Enter on the clip to play it." "" \
        "Tip: rename the file before adding; the clip and its" \
        "theme are named after the file."
      return ;;
    *"Remove a video"*)
      printf '%s\n' "Remove a video" "$rule" "" \
        "Select the video to remove from the library." "" \
        "Deletes its per-clip theme, every library copy, and its" \
        "cycle-list entry. If it is the playing one, another" \
        "video takes over first. Your original clip file is" \
        "never touched."
      return ;;
    *"How to use"*)
      printf '%s\n' "Keys" "$rule" "" \
        "  Enter   play (video + palette)" \
        "  r       remove a video (picker)" \
        "  a       add a video" \
        "  ?       help" \
        "  q/Esc   quit" "" \
        "  up/down or j/k  move · type to filter"
      return ;;
  esac
  name=$(line_to_name "$plain")
  row=$(grep -P "^\Q${name}\E\t" "$SESSION/library.tsv" 2>/dev/null | head -1) || true
  if [[ -z $row ]]; then
    printf 'unknown: %s\n' "$name"; return
  fi
  IFS=$'\t' read -r name theme file kind <<<"$row"
  status="idle"
  [[ $name == "$CUR_BASE" && $theme == "$CUR_THEME" ]] && status="PLAYING"
  printf '%s\n' "$name" "$rule" "" \
    "theme     $theme" \
    "kind      $(tag_for "$kind")" \
    "status    $status" \
    "media     $(clip_meta "$file")" \
    "" \
    "Enter → play · r → remove"
}
export -f preview_cmd

# ---------------------------------------------------------------- actions ----
do_play() { # <name>
  local name=$1 row theme file
  row=$(grep -P "^\Q${name}\E\t" "$SESSION/library.tsv" 2>/dev/null | head -1) || true
  [[ -z $row ]] && return 1
  IFS=$'\t' read -r _ theme file _ <<<"$row"
  if [[ $theme == "$CUR_THEME" ]]; then
    omarchy theme bg set "$file"
  else
    omarchy theme set "$theme"
    omarchy theme bg set "$file"
  fi
  FEEDBACK="playing $name · $theme"
}

do_add() {
  local start=$HOME/Videos
  [[ -d $start ]] || start=$HOME
  local f
  f=$(gum file "$start") || return 0
  [[ -z $f ]] && return 0
  local name=${f##*/}; name=${name%.*}
  # The plugin has no volume control: a clip with an audio track would be
  # heard. Offer to drop the track (lossless remux) before adding; if the
  # user declines, abort (the add would fail anyway).
  local strip=""
  if ffprobe -v error -select_streams a -show_entries stream=codec_type \
       "$f" 2>/dev/null | grep -q audio; then
    if gum confirm --title "The clip has an audio track" \
         --description "'$name' carries audio; the plugin would play it. Drop the audio track (lossless remux)?" \
         --affirmative "Drop audio" --negative "Cancel"; then
      strip="--strip-audio"
    else
      FEEDBACK="aborted: $name has an audio track"
      return 0
    fi
  fi
  # --no-activate: adding must not yank the current wallpaper (the user can
  # play the new clip with Enter when they want).
  if gum spin --spinner dot --title "creating theme (Aether + library mirror)" \
       --show-output -- "$PLUGIN_BIN/video-add.sh" $strip --no-activate "$f" 2>&1; then
    FEEDBACK="added $name"
  else
    FEEDBACK="add failed: $name"
  fi
}

do_remove() { # <name>
  local name=$1
  gum confirm --title "Remove $name?" \
    --description "Deletes its per-clip theme, library copies and cycle entry. Your original clip file is untouched." \
    --affirmative "Remove" --negative "Cancel" || return 0
  if gum spin --spinner dot --title "removing $name" \
       --show-output -- "$PLUGIN_BIN/video-remove.sh" "$name" 2>&1; then
    FEEDBACK="removed $name"
  else
    FEEDBACK="remove failed: $name"
  fi
}

# Picker used both by the "Remove a video" entry and the 'r' key: lists only
# clips (with preview), the user chooses, then do_remove confirms. No
# dependency on the preview's highlight state.
remove_picker() {
  local pick
  pick=$(build_clips_only | fzf \
      --height "90%" --border \
      --border-label " select a video to remove " --border-label-pos 3 \
      --prompt "  " --ansi \
      --preview "preview_cmd {}" \
      --preview-window "right:33%,border-rounded" \
      --bind "q:abort" \
      --color "$(fzf_colors)" \
      2>/dev/null) || pick=""
  [[ -n $pick ]] && do_remove "$(line_to_name "$pick")"
}

show_help() {
  local text
  text=$(cat <<'EOF'
How to use
───────────────────────────────────────────────
  Navigate    up/down  ·  j/k  ·  type to filter
  Play        Enter on a clip — switches the video
              and the palette (per-clip themes)
  Remove      r, or the "Remove a video" entry —
              opens a picker to choose the clip
  Add         a, or the "Add a video" entry — file
              picker, then Aether extracts the
              palette and registers the clip
  Help        ?   ·   Quit  q / Esc

  [own palette]  the clip has its own theme; its
  colors were extracted from the clip (Aether)
  [library]      the clip plays in the library
  theme's palette

  Add: any video works (mp4/mov/webm). If it has
  an audio track you are asked to drop it (the
  plugin has no volume control). Adding never
  changes the current wallpaper — Enter on the
  clip plays it. The clip is mirrored into the
  library theme with hardlinks (zero extra
  space).
  Remove: deletes the per-clip theme, library
  copies and the cycle-list entry. If the clip
  is the playing one, another video takes over
  first. Your original file is never touched.
EOF
)
  clear
  gum style --border rounded --border foreground:"$ACC" \
    --margin "0 1" --padding "1 2" --width 64 -- "$text"
  read -r -p "  press Enter to go back…" _ 2>/dev/null || true
}

# ------------------------------------------------------------------- main ----
fzf_colors() {
  # truecolor scheme from the active palette (fzf wants #RRGGBB)
  printf 'fg:#%s,bg:#%s,fg+:#%s,header:#%s,info:#%s,query:#%s,pointer:#%s,marker:#%s,prompt:#%s,border:#%s' \
    "${TXT#'#'}" "${BG#'#'}" "${ACC#'#'}" "${ACC#'#'}" "${MUT#'#'}" "${ACC#'#'}" "${ACC#'#'}" "${ACC#'#'}" "${ACC#'#'}" "${ACC#'#'}"
}

main() {
  local FEEDBACK="" out rc action
  while true; do
    load_palette
    declare_icons
    scan_library
    current_state
    local n; n=$(wc -l < "$SESSION/library.tsv")

    local label=" $I_FILM  video library · $n clips · theme: $CUR_THEME"
    [[ -n $FEEDBACK ]] && label="  $FEEDBACK    $label"

    rm -f "$SESSION/action"
    rc=0
    out=$(build_list | fzf \
        --height "90%" \
        --border \
        --border-label "$label" \
        --border-label-pos 3 \
        --prompt "filter: " \
        --ansi \
        --preview "preview_cmd {}" \
        --preview-window "right:33%,border-rounded" \
        --bind "a:execute-silent(echo ADD > $SESSION/action)+abort" \
        --bind "r:execute-silent(echo REMOVE > $SESSION/action)+abort" \
        --bind "?:execute-silent(echo HELP > $SESSION/action)+abort" \
        --bind "q:abort" \
        --color "$(fzf_colors)" \
        2>/dev/null) || rc=$?

    action=$(cat "$SESSION/action" 2>/dev/null) || action=""
    rm -f "$SESSION/action"

    # shortcut key (a/r/?) → abort with marker
    if [[ -n $action ]]; then
      FEEDBACK=""
      case $action in
        ADD) do_add ;;
        REMOVE) remove_picker ;;
        HELP) show_help ;;
      esac
      continue
    fi

    # Enter on an item → normal selection; else quit
    if [[ $rc -ne 0 || -z $out ]]; then
      break
    fi
    FEEDBACK=""

    case $out in
      *"Add a video"*) do_add ;;
      *"Remove a video"*) remove_picker ;;
      *"How to use"*) show_help ;;
      *)
        do_play "$(line_to_name "$out")" || true
        ;;
    esac
  done
}

main "$@"
