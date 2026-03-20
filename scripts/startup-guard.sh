#!/bin/bash
# Startup guard — exits 0 (allow) if container has been up long enough, exits 1 (skip) if still warming up
# Usage: startup-guard.sh [min_uptime_seconds] && your-actual-script.sh
# Default: 180 seconds (3 minutes) — enough for all 18 agents to finish QMD memory init

MIN_UPTIME=${1:-180}
CONTAINER="openclaw-openclaw-gateway-1"

# Get container start time
STARTED_AT=$(docker inspect --format '{{.State.StartedAt}}' "$CONTAINER" 2>/dev/null) || exit 1
START_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null) || exit 1
NOW_EPOCH=$(date +%s)
UPTIME=$((NOW_EPOCH - START_EPOCH))

if [ "$UPTIME" -lt "$MIN_UPTIME" ]; then
  echo "startup-guard: container up ${UPTIME}s < ${MIN_UPTIME}s minimum, skipping" >&2
  exit 1
fi

exit 0
