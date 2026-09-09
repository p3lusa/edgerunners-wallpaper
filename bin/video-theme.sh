#!/usr/bin/env bash
# video-theme.sh — create an Omarchy theme from a video clip.
#
# Generates a complete, palette-matched Omarchy theme from a single video:
# a poster frame is extracted, Aether derives the color palette from it, and
# the clip is installed as the theme's looping video wallpaper.
#
# Usage:
#   video-theme.sh <clip.mp4> <theme-name>
#
# Example:
#   video-theme.sh ~/Videos/aurora.mp4 my-aurora
#   omarchy theme set my-aurora   # (already done by the script)
#
# Requirements: aether, ffmpeg, omarchy, and the p3lu.video-background
# plugin (to render the videos/ directory — without it, the theme shows
# the poster image instead).
#
# Notes:
#   - The theme is installed to ~/.config/omarchy/themes/<theme-name>/ and
#     marked as Aether-managed (.aether-managed), so future Aether runs
#     recognize it.
#   - Theme names must match [A-Za-z0-9][A-Za-z0-9_.-]{0,63} (lowercased).
#   - To update the clip later, replace the file in the theme's videos/
#     directory and run: omarchy theme set <theme-name>

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $(basename "$0") <clip.mp4> <theme-name>" >&2
  exit 2
fi

clip="$1"
name="$2"

# --- sanity checks ------------------------------------------------------------
if [[ ! -f "$clip" ]]; then
  echo "error: clip not found: $clip" >&2
  exit 1
fi
if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]]; then
  echo "error: invalid theme name: $name" >&2
  echo "       (letters, digits, '_', '.', '-'; must start with a letter/digit)" >&2
  exit 1
fi
for tool in aether ffmpeg ffprobe omarchy; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool not found: $tool" >&2
    exit 1
  fi
done

name="$(tr '[:upper:]' '[:lower:]' <<< "$name")"
theme_src="${HOME}/.config/omarchy/themes/${name}"
if [[ -d "$theme_src" ]]; then
  echo "error: theme already exists: $name ($theme_src)" >&2
  echo "       delete it or pick another name." >&2
  exit 1
fi

# --- 1. poster frame ------------------------------------------------------------
# A frame from ~10% into the clip: representative of the whole loop for
# seamless loops, and stable. Falls back to 0s for very short clips.
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
poster="${tmpdir}/poster.png"

duration="$(ffprobe -v error -show_entries format=duration \
  -of default=nw=1:nk=1 "$clip" 2>/dev/null || echo 0)"
seek="$(awk -v d="${duration:-0}" 'BEGIN { s = d * 0.1; if (s < 0) s = 0; printf "%.2f", s }')"
if ! ffmpeg -hide_banner -loglevel error -ss "$seek" -i "$clip" \
    -frames:v 1 -y "$poster" || [[ ! -s "$poster" ]]; then
  echo "error: could not extract a poster frame from $clip" >&2
  exit 1
fi

# --- 2. generate + install theme --------------------------------------------------
# Aether writes a full theme (colors.toml + terminal/tool configs) to a temp
# dir; we move it into Omarchy's user themes root and mark it Aether-managed
# (same marker aether --handle-url would leave behind).
gen_dir="${tmpdir}/theme"
if ! aether --generate "$poster" --no-apply --output "$gen_dir" >/dev/null; then
  echo "error: aether failed to generate a theme from the poster" >&2
  exit 1
fi
if [[ ! -f "$gen_dir/colors.toml" ]]; then
  echo "error: aether produced no colors.toml in $gen_dir" >&2
  exit 1
fi
mkdir -p "$theme_src"
cp -r "$gen_dir/." "$theme_src/"
echo "aether" > "${theme_src}/.aether-managed"

# --- 3. attach the video -----------------------------------------------------------
mkdir -p "${theme_src}/videos"
cp "$clip" "${theme_src}/videos/$(basename "$clip")"

# --- 4. activate ---------------------------------------------------------------------
if ! omarchy theme set "$name"; then
  echo "error: omarchy theme set $name failed" >&2
  exit 1
fi

echo
echo "Theme '$name' is active."
echo "  source: $theme_src"
echo "  video : videos/$(basename "$clip")"
echo "  switch back: omarchy theme set <previous-theme>"
