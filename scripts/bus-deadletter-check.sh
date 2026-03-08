#!/usr/bin/env bash
# bus-deadletter-check.sh — Flag stalled bus tasks older than 2 hours
# Intent: Observable [I17], Reliable [I05].
set -eo pipefail

LOG="/root/.openclaw/logs/bus-deadletter.log"
TASK_DIR="/tmp/openclaw-bus/tasks"
mkdir -p "$(dirname "$LOG")"

[ ! -d "$TASK_DIR" ] && exit 0

NOW=$(date +%s)
STALE_COUNT=0

shopt -s nullglob
for f in "$TASK_DIR"/*.json; do
  CREATED=$(python3 -c "import json; print(json.load(open('$f')).get('created',''))" 2>/dev/null || echo "")
  if [ -n "$CREATED" ]; then
    TASK_EPOCH=$(date -d "$CREATED" +%s 2>/dev/null || echo 0)
    AGE_HOURS=$(( (NOW - TASK_EPOCH) / 3600 ))
    if [ "$AGE_HOURS" -ge 2 ]; then
      TASK_ID=$(python3 -c "import json; print(json.load(open('$f')).get('id','unknown'))" 2>/dev/null)
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] STALE: $TASK_ID (${AGE_HOURS}h old)" >> "$LOG"
      STALE_COUNT=$((STALE_COUNT + 1))
    fi
  fi
done

if [ "$STALE_COUNT" -gt 0 ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $STALE_COUNT stalled tasks on bus" >> "$LOG"
fi
