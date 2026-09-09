# Video Background

Desktop wallpaper renderer for [Omarchy](https://omarchy.org). Drop `videos/*.mp4` into any theme's directory and that theme plays them as a looping video wallpaper; themes without a `videos/` directory behave exactly like the stock image background.

## Features

- Plays the active theme's looping video on the `WlrLayer.Background` layer, per monitor (multi-monitor ready, hardware-accelerated decode via the Qt FFmpeg backend).
- Seamless image fallback: no videos, a corrupt file, or a decode error degrades to the theme's static background — never a black screen.
- Clip cycling: a theme can ship several clips; `omarchy theme bg next` advances to the next one.
- Power-friendly: the video pauses while the session is locked or idle, and resumes in place when the desktop returns.
- The video always matches the background: the clip is derived from the active background image (paired by file name), so cycling with `omarchy theme bg next` advances both in lockstep and they can never desync. The active clip also survives shell restarts for free (the background symlink is Omarchy's own persisted state).
- Drop-in replacement for the built-in `omarchy.background` service: same layer, same namespace, same IPC surface (`themeTransition`, background symlink tracking, transitions).

## Requirements

- Omarchy (this is an Omarchy shell plugin).
- No external dependencies — rendering uses the system Qt 6 Multimedia (FFmpeg backend), already part of Omarchy.

### Video assets

Videos are your own (any legal source). The bundled [video-wallpaper theme](https://github.com/p3lusa/video-wallpaper) ships three CC0/CC BY sample clips from Wikimedia Commons. Recommended spec (what the sample theme uses):

| Property | Value |
|---|---|
| Codec | H.264 (hardware-decoded on most GPUs) |
| Resolution | 1080p for laptop/1080p targets, 1440p or higher for 1440p+ panels |
| Frame rate | 24–30 fps |
| Bitrate | ~5–8 Mbps (CRF 20–23) |
| Audio | **none** — the Qt FFmpeg `MediaPlayer` exposes no mute/volume API, so clips must have no audio track |
| Length | 8–40 s, ideally a seamless loop |

A convenient encode:

```bash
ffmpeg -i input.mp4 -an -c:v libx264 -crf 23 -preset slow \
  -r 30 -vf "scale=1920:1080" -t 20 -movflags +faststart output.mp4
```

## Install

```bash
omarchy plugin add <this-repo-url> --enable
omarchy plugin disable omarchy.background
```

The first command installs and enables the plugin; the second hands the background layer over to it (only one background renderer should be active — they share the same layer namespace).

## Creating a theme from your own clip (Aether)

This plugin ships a helper, `bin/video-theme.sh` (installed at `~/.config/omarchy/plugins/p3lu.video-background/bin/video-theme.sh`), that turns any clip into a complete, palette-matched Omarchy theme in one command:

```bash
video-theme.sh <clip.mp4> <theme-name>
```

It extracts a poster frame from the clip, runs [Aether](https://github.com/omacom/aether) to derive the color palette and generate the full theme (terminal, bar, lock screen, …), installs it to `~/.config/omarchy/themes/<theme-name>/` with the clip in its `videos/` directory, and activates it. Result: video wallpaper and every accent color on the system come from the same clip.

Prerequisites: `aether` in `PATH`, `ffmpeg`/`ffprobe`, and this plugin enabled (without it the theme shows the poster image instead of the video). To update the clip later, replace the file in the theme's `videos/` directory and run `omarchy theme set <theme-name>`.

## Usage

1. Put clips in the theme's source `videos/` directory — for an
   `omarchy theme install`ed theme that is
   `~/.config/omarchy/themes/<theme>/videos/` (create it if needed).
2. Switch to that theme: `omarchy theme set <theme>` (this re-stages the
   theme, including your clips).
3. Cycle clips: `omarchy theme bg next`.

With a theme that has no `videos/` directory (the default for most themes), the plugin renders the static background exactly like the stock service — you can leave it enabled permanently.

## Uninstall

```bash
omarchy plugin remove p3lu.video-background --yes
omarchy plugin enable omarchy.background
```

## How it works

The plugin resolves the active theme's `videos/*.mp4` files on every background/theme change (IPC + short poll of the `current/background` symlink). The playing clip is **derived from the current background image** by matching file base names, so the video and the image can never fall out of sync — the background symlink is the single source of truth (and Omarchy's persisted state, so the clip survives shell restarts). For each panel it creates one `MediaPlayer` + `VideoOutput` (`Qt.KeepAspectRatioByExpanding` fill), starts the video only after the first decoded frame (the static background stays visible underneath until then), and pauses playback while the session is locked or idle.

The background layer can occasionally end up with a stale (uncommitted) surface buffer after a shell restart or a long time parked behind the lock screen, which would leave a flat desktop. As a safeguard, at startup and on every unlock the plugin forces an invisible re-render (the reveal transition runs with the same image on both sides, so nothing changes visually), which re-commits the surface if it was stale — the wallpaper always shows up.

## Known limitations

- No crossfade between clips (the previous frame stays visible for a few hundred ms while the next clip's first frame decodes).
- One clip is active on all monitors (per-monitor clip selection is not implemented).
- A video only plays while its paired background image (same base name) is the active background — videos without a paired image are ignored.
- If you run `omarchy refresh shell` by hand, re-apply the state with:
  ```bash
  omarchy plugin enable p3lu.video-background
  omarchy plugin disable omarchy.background
  ```
  (The `video-wallpaper` theme ships a `post-update` hook that does this automatically after `omarchy update` when its theme is active.)

## License

[MIT](LICENSE). This plugin is derived from the stock `omarchy.background` service of [Omarchy](https://github.com/omacom/omarchy) (MIT); the video branch is layered on top of its image renderer. Thanks to the Omarchy team.
