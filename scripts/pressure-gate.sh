#!/bin/bash
# Pressure Gate — wrapper for crons that call agents or APIs
# Usage: pressure-gate.sh <command> [args...]
# If pressure mode is active, defers the work and exits 0
# If pressure mode is not active, runs the command normally
#
# Example crontab entry:
#   30 8 * * * /root/.openclaw/scripts/pressure-gate.sh /root/.openclaw/scripts/ai-news.sh

PRESSURE_FLAG="/root/.openclaw/pressure-mode"
LOG="/root/.openclaw/logs/pressure-relief.log"

if [ $# -eq 0 ]; then
  echo "Usage: pressure-gate.sh <command> [args...]"
  exit 1
fi

if [ -f "$PRESSURE_FLAG" ]; then
  SINCE=$(python3 -c "import json; print(json.load(open('$PRESSURE_FLAG')).get('since','unknown'))" 2>/dev/null || echo "unknown")
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) DEFERRED: $* (pressure mode since $SINCE)" >> "$LOG"
  exit 0
fi

exec "$@"
