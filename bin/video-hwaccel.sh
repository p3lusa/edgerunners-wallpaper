#!/usr/bin/env bash
# video-hwaccel.sh — detect the user's GPU and write the Qt FFmpeg
# hardware-acceleration environment for the video wallpaper.
#
# The wallpaper is decoded by Qt Multimedia's FFmpeg backend (Background.qml's
# MediaPlayer), NOT by any .sh script. To make it use the GPU we set the
# QT_FFMPEG_* environment variables that the Qt FFmpeg plugin reads:
#   QT_FFMPEG_DECODING_HW_DEVICE_TYPES   (e.g. "vaapi" or "cuda")
#   QT_FFMPEG_HW_ALLOW_PROFILE_MISMATCH  (broaden VAAPI profile coverage)
#
# PHASE 1 (this script as-is): DETECTION only. It detects the GPU family and
# writes hwaccel.env + hwaccel.log next to this script. It does NOT yet inject
# the env into the omarchy-shell session (that is phase 2, the `--apply` path).
#
# Design (see docs/PLAN-hwaccel-gpu.md):
#   NVIDIA (dGPU)          -> cuda
#   Intel iGPU / AMD (iGPU) -> vaapi   (VAAPI covers both; it is the single
#                                      path for the iGPUs that dominate laptops)
#   nothing usable         -> cpu      (write a comment-only env; never break)
# The backend list is short and vendor-specific (a decision the user made); Qt
# itself falls back to CPU decode if the chosen HW backend fails.

set -euo pipefail

PLUGIN_BIN="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PLUGIN_ROOT="$(dirname "$PLUGIN_BIN")"
ENV_FILE="$PLUGIN_ROOT/hwaccel.env"
LOG_FILE="$PLUGIN_ROOT/hwaccel.log"

mkdir -p "$PLUGIN_ROOT"
: > "$LOG_FILE"

log() { printf '%s\n' "$*" >> "$LOG_FILE"; printf '%s\n' "$*"; }

# --- GPU detection -----------------------------------------------------------
vendor=""   # nvidia | vaapi | ""
gpu=""      # amd | intel | unknown (only for vaapi)
backend=""  # cuda | vaapi | cpu
render_node=""

lspci_out=""
if command -v lspci >/dev/null 2>&1; then
  lspci_out="$(lspci 2>/dev/null || true)"
fi
lsmod_mods="$(lsmod 2>/dev/null | awk 'NR>0{print $1}' || true)"
has_mod() { grep -qx "$1" <<<"$lsmod_mods" 2>/dev/null; }

# NVIDIA: nvidia-smi is the gold standard; /dev/nvidia0 and the in-use driver
# are fallbacks for headless-ish setups.
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  vendor="nvidia"; backend="cuda"
elif [[ -e /dev/nvidia0 ]]; then
  vendor="nvidia"; backend="cuda"
elif grep -qi 'nvidia' <<<"$lspci_out" && grep -qE 'Kernel driver in use: nvidia' <<<"$lspci_out"; then
  vendor="nvidia"; backend="cuda"
fi

# VAAPI: needs a render node (/dev/dri/renderD*) plus an AMD or Intel driver.
if [[ -z $vendor ]]; then
  render_nodes="$(ls -1 /dev/dri/renderD* 2>/dev/null | sort || true)"
  if [[ -n $render_nodes ]]; then
    render_node="$(head -n1 <<<"$render_nodes")"
    if has_mod amdgpu || grep -qiE 'AMD/ATI|Advanced Micro Devices' <<<"$lspci_out"; then
      gpu="amd";  vendor="vaapi"; backend="vaapi"
    elif has_mod i915 || grep -qiE 'Intel' <<<"$lspci_out"; then
      gpu="intel"; vendor="vaapi"; backend="vaapi"
    else
      gpu="unknown"; vendor="vaapi"; backend="vaapi"
    fi
  fi
fi

# No GPU hwaccel available: leave the backend at Qt's CPU default.
if [[ -z $vendor ]]; then
  vendor="none"; gpu="none"; backend="cpu"; render_node=""
fi

# --- write hwaccel.env -------------------------------------------------------
if [[ $backend == "cuda" ]]; then
  env_body="QT_FFMPEG_DECODING_HW_DEVICE_TYPES=cuda"
elif [[ $backend == "vaapi" ]]; then
  env_body="QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi
QT_FFMPEG_HW_ALLOW_PROFILE_MISMATCH=1"
else
  env_body="# no GPU hwaccel detected -> CPU decode (Qt default)"
fi
printf '%s\n' "$env_body" > "$ENV_FILE"

# --- log ---------------------------------------------------------------------
log "video-hwaccel: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "  gpu:         ${gpu}"
log "  vendor:      ${vendor}"
log "  backend:     ${backend}"
log "  render node: ${render_node:-n/a}"
log "  env file:    ${ENV_FILE}"
log "  env vars:"
sed 's/^/      /' <<<"$env_body"
log ""
log "  STATUS: phase 1 = detection only; env NOT yet applied to the session."
log "          (run 'video-hwaccel.sh --apply' once phase 2 lands.)"

exit 0
