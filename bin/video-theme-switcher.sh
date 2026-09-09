#!/usr/bin/env bash
# video-theme-switcher.sh — theme switcher that hides per-clip video themes.
#
# Same UI and behavior as omarchy-theme-switcher, except that themes created
# by video-theme.sh (they carry a .video-theme marker) are not listed: they
# are reached through the video tools (the video switcher, video-next,
# video-prev), not through the stock theme selector. Everything else —
# normal themes, stock themes, and the multi-clip video-wallpaper theme —
# appears exactly as in the stock switcher.
#
# Selected via the same image picker; the caller applies the choice with
# `omarchy theme set <name>`, exactly like the stock flow.

set -euo pipefail

USER_THEMES_PATH="$HOME/.config/omarchy/themes"
OMARCHY_THEMES_PATH="${OMARCHY_PATH:-/usr/share/omarchy}/themes"
CACHE_PATH="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/video-theme-selector"
preview_dir="$CACHE_PATH/previews"

# Same preview discovery as the stock switcher: a preview.* file in the
# theme root, else the first image in backgrounds/.
find_preview() {
  local theme_path="$1"
  local preview preview_name
  for preview_name in preview.png preview.jpg preview.jpeg preview.webp preview.gif preview.bmp; do
    preview=$(find -L "$theme_path" -maxdepth 1 -type f -iname "$preview_name" -print -quit 2>/dev/null)
    if [[ -n $preview ]]; then
      printf '%s\n' "$preview"
      return
    fi
  done
  if [[ -d $theme_path/backgrounds ]]; then
    find -L "$theme_path/backgrounds" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \
         -o -iname '*.bmp' -o -iname '*.webp' \) -print 2>/dev/null | sort | head -n 1
  fi
}

# Visible themes: every entry in both theme paths that is NOT a marked
# per-clip video theme.
themes=()
for theme_dir in "$USER_THEMES_PATH" "$OMARCHY_THEMES_PATH"; do
  if [[ -d $theme_dir ]]; then
    while IFS= read -r -d '' theme_path; do
      if [[ -e "$theme_path/.video-theme" ]]; then
        continue
      fi
      themes+=("$theme_path")
    done < <(find -L "$theme_dir" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print0 2>/dev/null | sort -z)
  fi
done

# Rebuild the preview cache (a symlink per theme). The set of themes is
# small and this only runs when the user opens the menu, so a full rebuild
# each time is simpler than the stock signature caching.
rm -rf "$preview_dir"
mkdir -p "$preview_dir"
for theme_path in ${themes[@]+"${themes[@]}"}; do
  theme_name=${theme_path##*/}
  preview=$(find_preview "$theme_path")
  if [[ -z $preview && -d "$OMARCHY_THEMES_PATH/$theme_name" ]]; then
    preview=$(find_preview "$OMARCHY_THEMES_PATH/$theme_name")
  fi
  if [[ -n $preview ]]; then
    ext="${preview##*.}"; ext="${ext,,}"
    ln -sf "$preview" "$preview_dir/$theme_name.$ext"
  fi
done

current_theme=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
selected_preview=""
for extension in png jpg jpeg webp gif bmp; do
  if [[ -e $preview_dir/$current_theme.$extension ]]; then
    selected_preview="$preview_dir/$current_theme.$extension"
    break
  fi
done

exec omarchy-menu-images \
  --print-name --show-labels --filterable --lazy-thumbnails \
  --selected "$selected_preview" "$preview_dir"
