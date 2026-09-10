#!/usr/bin/env bash
# video-hwaccel.sh -- detect the user's GPU(s) and write the Qt FFmpeg
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
# the env into the omarchy-shell session (that is phase 2, the --apply path).
#
# Design (see docs/PLAN-hwaccel-gpu.md):
#   NVIDIA (dedicated)                 -> cuda   (NVDEC lives on the dGPU)
#   Intel iGPU / AMD (iGPU or dGPU)    -> vaapi  (VAAPI covers both; it is the
#                                                single path for the iGPUs that
#                                                dominate laptops)
#   nothing usable                     -> cpu    (comment-only env; never break)
# The backend list is short and vendor-specific (user decision); Qt itself
# falls back to CPU decode if the chosen HW backend fails.
#
# Both integrated and dedicated GPUs are ENUMERATED and logged. On a hybrid
# (iGPU+dGPU) the script records every GPU + its render node and picks the best
# VAAPI node. The Qt FFmpeg backend cannot be pinned to a specific render node
# (no such env var), so on a hybrid it uses the session default node -- the log
# still tells you exactly what hardware is present.

set -euo pipefail

PLUGIN_BIN="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PLUGIN_ROOT="$(dirname "$PLUGIN_BIN")"
ENV_FILE="$PLUGIN_ROOT/hwaccel.env"
LOG_FILE="$PLUGIN_ROOT/hwaccel.log"
# DRM root is overridable for testability / exotic layouts (default /dev/dri).
DRI_ROOT="${VIDEO_HWACCEL_DRI_ROOT:-/dev/dri}"

mkdir -p "$PLUGIN_ROOT"
: > "$LOG_FILE"

log() { printf '%s\n' "$*" >> "$LOG_FILE"; printf '%s\n' "$*"; }

# --- helpers -----------------------------------------------------------------
lsmod_mods="$(lsmod 2>/dev/null | awk 'NR>0{print $1}' || true)"
has_mod() { grep -qx "$1" <<<"$lsmod_mods" 2>/dev/null; }

# classify a full lspci vendor line -> nvidia | amd | intel | other
classify() {
  if   grep -qi 'nvidia' <<<"$1"; then echo nvidia
  elif grep -qiE 'advanced micro devices|amd/ati' <<<"$1"; then echo amd
  elif grep -qi 'intel'  <<<"$1"; then echo intel
  else echo other; fi
}

# normalise a PCI id to "B:D.F" (drop the "0000:" domain and any -card/-render)
norm_pci() {
  local p="$1"
  p="${p#pci-}"; p="${p%%-card}"; p="${p%%-render}"
  p="${p#0000:}"
  printf '%s' "$p"
}

# --- GPU discovery: enumerate EVERY display GPU ------------------------------
# lspci -nnk prints one block per device; the first line carries the PCI id and
# vendor, a later line carries "Kernel driver in use: <mod>". We collect every
# VGA/3D/Display controller line together with its in-use driver.
lspci_all=""
declare -a GPU_PCI=() GPU_DRV=() GPU_LINE=()
if command -v lspci >/dev/null 2>&1; then
  lspci_all="$(lspci -nnk 2>/dev/null || true)"
  _cur_pci=""; _cur_drv=""; _cur_line=""; _cur_keep=false
  while IFS= read -r _line; do
    # A line starting with a PCI address ends the previous display block:
    # flush it first. Only VGA/3D/Display controllers count as GPUs.
    if [[ $_line =~ ^[0-9a-fA-F]{1,4}:[0-9a-fA-F]{2}\.[0-9a-fA-F] ]]; then
      if [[ -n $_cur_pci && -n $_cur_line ]]; then
        GPU_PCI+=("$_cur_pci"); GPU_DRV+=("$_cur_drv"); GPU_LINE+=("$_cur_line")
      fi
      _cur_pci=""; _cur_keep=false
      if [[ $_line == *"VGA compatible controller"* \
           || $_line == *"3D controller"* \
           || $_line == *"Display controller"* ]]; then
        _cur_pci="${_line%% *}"
        _cur_line="$_line"
        _cur_drv=""
        _cur_keep=true
      fi
      continue
    fi
    case "$_line" in
      *"Kernel driver in use: "*)
        if [[ -n $_cur_pci && $_cur_keep == true ]]; then
          _d="${_line##*: }"
          _cur_drv="${_d// /}"
        fi
        ;;
    esac
    # a non-address line that isn't a display controller / driver note resets
    # the block so a stray "Kernel driver" from another device doesn't leak in.
    if [[ -n $_cur_pci && $_cur_keep == true ]]; then
      if [[ $_line != *"Kernel driver in use:"* ]]; then
        # keep going; the next address line will flush. Only reset on a
        # blank line (block separator).
        [[ -z $_line ]] && { _cur_pci=""; _cur_keep=false; }
      fi
    fi
  done <<<"$lspci_all"
  if [[ -n $_cur_pci && -n $_cur_line && $_cur_keep == true ]]; then
    GPU_PCI+=("$_cur_pci"); GPU_DRV+=("$_cur_drv"); GPU_LINE+=("$_cur_line")
  fi
fi

# Map each VAAPI render node to the PCI GPU it belongs to (via by-path symlinks).
declare -A NODE_PCI=() PCI_NODE=()
for f in "$DRI_ROOT"/by-path/*-render; do
  [[ -e $f ]] || continue
  pci="$(norm_pci "$(basename "$f")")"
  node="$(basename "$(readlink -f "$f")")"
  NODE_PCI["$node"]="$pci"; PCI_NODE["$pci"]="$node"
done
render_nodes="$(ls -1 "$DRI_ROOT"/renderD* 2>/dev/null | sort || true)"

# --- pick the decode backend --------------------------------------------------
vendor=""   # nvidia | vaapi | none
gpu=""      # amd | intel | unknown (only for vaapi)
backend=""  # cuda | vaapi | cpu
render_node=""

# 1) NVIDIA wins outright: its NVDEC lives on the dedicated GPU.
nvidia_ok=false
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then nvidia_ok=true; fi
[[ -e /dev/nvidia0 ]] && nvidia_ok=true
for i in "${!GPU_PCI[@]}"; do
  if [[ $(classify "${GPU_LINE[$i]}") == nvidia && -n ${GPU_DRV[$i]:-} ]]; then
    nvidia_ok=true; break
  fi
done
if $nvidia_ok; then
  vendor="nvidia"; backend="cuda"; gpu="nvidia"
fi

# 2) Else VAAPI if a render node exists. Prefer a non-Intel (dedicated) node
#    when there are several, so a hybrid iGPU+dGPU uses the dGPU.
if [[ -z $vendor && -n $render_nodes ]]; then
  vendor="vaapi"; backend="vaapi"
  best=""
  while IFS= read -r n; do
    [[ -n $n ]] || continue
    p="${NODE_PCI[$(basename "$n")]:-}"; v=""
    if [[ -n $p ]]; then
      for i in "${!GPU_PCI[@]}"; do
        [[ ${GPU_PCI[$i]} == "$p" ]] && { v="$(classify "${GPU_LINE[$i]}")"; break; }
      done
    fi
    if [[ -z $best ]]; then best="$n"
    elif [[ -n $v && $v != intel ]]; then best="$n"; fi
  done <<<"$render_nodes"
  render_node="$best"
  if has_mod amdgpu || grep -qiE 'advanced micro devices|amd/ati' <<<"$lspci_all"; then gpu="amd"
  elif has_mod i915 || grep -qi 'intel' <<<"$lspci_all"; then gpu="intel"
  else gpu="unknown"; fi
fi

# 3) No GPU hwaccel available: leave the backend at Qt's CPU default.
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
if [[ ${#GPU_PCI[@]} -gt 0 ]]; then
  log "  GPUs detected:"
  for i in "${!GPU_PCI[@]}"; do
    v="$(classify "${GPU_LINE[$i]}")"
    drv="${GPU_DRV[$i]:-<none>}"
    node="${PCI_NODE[${GPU_PCI[$i]}]:-<no render node>}"
    log "    ${GPU_PCI[$i]}  ${v}  driver=${drv}  node=${node}"
  done
else
  log "  GPUs detected: none (lspci unavailable or no display GPU)"
fi
log "  backend:     ${backend}"
log "  gpu family:  ${gpu}"
log "  render node: ${render_node:-n/a}"
log "  env file:    ${ENV_FILE}"
log "  env vars:"
sed 's/^/      /' <<<"$env_body"
if [[ $backend == "vaapi" ]]; then
  _n_nodes=0
  [[ -n $render_nodes ]] && _n_nodes="$(grep -c . <<<"$render_nodes")"
  if [[ $_n_nodes -gt 1 ]]; then
    log ""
    log "  NOTE: multiple render nodes (hybrid iGPU+dGPU). The Qt FFmpeg backend"
    log "        cannot be pinned to a node, so VAAPI uses the session default"
    log "        node. The GPUs above show which node belongs to which chip."
  fi
fi
log ""
log "  STATUS: phase 1 = detection only; env NOT yet applied to the session."
log "          (run 'video-hwaccel.sh --apply' once phase 2 lands.)"

exit 0
