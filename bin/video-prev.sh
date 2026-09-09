#!/usr/bin/env bash
# video-prev.sh — activate the previous video theme (clip + palette) in the cycle.
# See video-cycle.sh for details.
exec "$(dirname "$0")/video-cycle.sh" prev
