# Video Background

Desktop wallpaper renderer for [Omarchy](https://omarchy.org). Drop `videos/*.mp4` into any theme's directory and that theme plays them as a looping video wallpaper; themes without a `videos/` directory behave exactly like the stock image background.

## Features

- Plays the active theme's looping video on the `WlrLayer.Background` layer, per monitor (multi-monitor ready, hardware-accelerated decode via the Qt FFmpeg backend).
- Seamless image fallback: no videos, a corrupt file, or a decode error degrades to the theme's static background — never a black screen.
- Clip cycling: a theme can ship several clips; `omarchy theme bg next` advances to the next one.
- Power-friendly: the video pauses while the session is locked or idle, and resumes in place when the desktop returns.
- The video always matches the background: the clip is derived from the active background image (paired by file name), so cycling with `omarchy theme bg next` advances both in lockstep and they can never desync. The active clip also survives shell restarts for free (the background symlink is Omarchy's own persisted state).
- Drop-in replacement for the built-in `omarchy.background` service: same layer, same namespace, same IPC surface (`themeTransition`, background symlink tracking, transitions).
- Self-installing keybindings (video switcher carousel + prev/next) that only appear when you use a video tool, and are fully removable.

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
video-theme.sh <clip.mp4> [theme-name]   # default name: video-<clip base>
```

It extracts a poster frame from the clip, runs [Aether](https://github.com/omacom/aether) to derive the color palette and generate the full theme (terminal, bar, lock screen, …), installs it to `~/.config/omarchy/themes/<theme-name>/` with the clip in its `videos/` directory, and activates it. Result: video wallpaper and every accent color on the system come from the same clip.

Prerequisites: `aether` in `PATH`, `ffmpeg`/`ffprobe`, and this plugin enabled (without it the theme shows the poster image instead of the video). Each created theme is registered in the cycle list, so `video-next` / `video-prev` can walk them (see Usage). To update the clip later, replace the file in the theme's `videos/` directory and run `omarchy theme set <theme-name>`.

## Usage

There are two workflows, and they can be mixed:

### One theme, many clips (one palette)

1. Put clips in the theme's source `videos/` directory — for an
   `omarchy theme install`ed theme that is
   `~/.config/omarchy/themes/<theme>/videos/` (create it if needed).
2. Switch to that theme: `omarchy theme set <theme>` (this re-stages the
   theme, including your clips).
3. Cycle clips: `omarchy theme bg next`.

All clips share the theme's palette.

### One theme per clip (each clip gets its own palette)

Clips usually don't share a mood, and a palette derived from clip A looks
wrong over clip B. The Aether helper solves this: each clip becomes its own
complete theme (see the Aether section above), and the plugin ships cycle
commands to walk them:

```bash
video-theme.sh ~/Videos/aurora.mp4      # creates + activates theme "video-aurora"
video-theme.sh ~/Videos/rain.mp4        # creates + activates theme "video-rain"
video-next                              # -> next clip + palette (wraps around)
video-prev                              # -> previous clip + palette
```

`video-next` / `video-prev` are installed at
`~/.config/omarchy/plugins/p3lu.video-background/bin/` (prepend that
directory to `PATH` to use them from a terminal). They walk the whole video
library — every clip of every theme that has videos, the same set the
switcher shows. Theme order: the cycle list first
(`~/.config/omarchy/video-themes`, maintained by `video-theme.sh`), then any
remaining video themes alphabetically; clips within a theme are
alphabetical. Switching to a clip of another theme is an `omarchy theme set`
(palette, background, and video all switch together with the usual animated
transition); switching to another clip of the current theme only changes the
video (the palette stays). The position survives shell restarts (the active
theme + background are Omarchy's own state).

#### Keybindings (self-installing)

The first time you run any video tool (`video-theme.sh`, `video-next`,
`video-prev`, or the selector below), the plugin installs three keybindings
into your `~/.config/hypr/bindings.lua` inside a self-contained marked block
(it never touches your own lines, and the block is refreshed in place if the
plugin moves):

| Key | Action |
|---|---|
| `Super+Ctrl+Alt+Space` | **Video switcher** — a carousel of your whole video library with poster previews (same UI as the wallpaper selector). The list is stable: it shows every clip of every theme that has videos, no matter which theme is active. Selecting a clip of the active theme switches the video (same palette); selecting a clip from another theme switches video + palette |
| `Super+Ctrl+Alt+Left` | Previous video (cycles through the whole library) |
| `Super+Ctrl+Alt+Right` | Next video (cycles through the whole library) |

They are installed on use rather than at plugin install: a plugin install
hook does not exist in Omarchy, and the plugin should not claim your
keymap until you actually use the feature. To install them manually:
`video-bindings.sh` (in the plugin's `bin/` directory); to remove them:
`video-bindings.sh --remove`.

#### The video switcher

`video-switcher.sh` is a thin wrapper around Omarchy's image menu (the same
UI as the wallpaper switcher). It builds a poster carousel of your whole
video library: every clip of every user theme that has videos (each clip is a
background poster with a paired video in `videos/`). The list is stable — it
does not change when you cycle themes — so after `video-next`/`video-prev`
you still see every video.

Entry naming: the active theme's clips appear by clip name; a theme with a
single clip appears by theme name; clips from other themes are prefixed with
the theme name (so the same clip in two themes stays two entries). The
currently playing video is preselected.

Choosing an entry: a clip of the active theme runs `omarchy theme bg set`
(video changes, palette stays); a clip from another theme runs `omarchy
theme set` + `omarchy theme bg set` (video and palette change together).

### No videos at all

With a theme that has no `videos/` directory (the default for most themes), the plugin renders the static background exactly like the stock service — you can leave it enabled permanently.

## Uninstall

```bash
# remove the installed keybindings (if you used any video tool)
~/.config/omarchy/plugins/p3lu.video-background/bin/video-bindings.sh --remove

omarchy plugin remove p3lu.video-background --yes
omarchy plugin enable omarchy.background
```

Themes created with `video-theme.sh` are regular Omarchy themes and can be
removed like any other: delete `~/.config/omarchy/themes/<theme-name>` (and
the cycle list entry in `~/.config/omarchy/video-themes`, if present).

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
