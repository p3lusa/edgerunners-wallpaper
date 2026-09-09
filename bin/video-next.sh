#!/usr/bin/env bash
# video-next.sh — activate the next video theme (clip + palette) in the cycle.
# See video-cycle.sh for details.
exec "$(dirname "$0")/video-cycle.sh" next
