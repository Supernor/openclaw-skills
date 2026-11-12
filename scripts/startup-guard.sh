#!/bin/bash
# #1903 regression tests: test-startup-guard.py
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
  # #1903: a restart done by gateway-memory-watchdog.py (kv marker written just before `docker compose restart`) is a self-healed event, not a failure.
  # Marker -> StartedAt gap observed 12-16 s (n=3+); window [-5 s, +120 s]. The marker is courtesy-grade input (ops.db is mode 666 and container-writable):
  # a wrong value can only turn the LABEL of a "container up <180s" skip from error to no_action for that one tick; the exit code (1, probe skipped) never changes.
  OPS_DB="${OPS_DB:-/root/.openclaw/ops.db}"
  LR=$(sqlite3 -readonly -cmd ".timeout 2000" "$OPS_DB" "SELECT value FROM kv WHERE key='gateway_watchdog_last_restart'" 2>/dev/null | head -c 41)
  if [[ "$LR" =~ ^[0-9]{9,11}(\.[0-9]{1,9})?$ ]] && awk -v s="$START_EPOCH" -v l="$LR" 'BEGIN{d=s-l; exit !(d>=-5 && d<=120)}'; then
    echo "RESULT_LABEL: no_action" >&2
    echo "startup-guard: container up ${UPTIME}s < ${MIN_UPTIME}s after a memory-watchdog restart (self-healed, marker ${LR}), skipping" >&2
  else
    echo "startup-guard: container up ${UPTIME}s < ${MIN_UPTIME}s minimum, skipping" >&2
  fi
  exit 1
fi

exit 0
