#!/usr/bin/env bash
# chart-stale-cron.sh — Daily stale chart scan (cron wrapper).
# Intent: Observable [I13]. Owner: Quartermaster (spec-quartermaster).
# Uses built-in `chart stale` command, logs results.

set -eo pipefail

LOGDIR="/root/.openclaw/logs"
LOGFILE="$LOGDIR/chart-stale.log"

mkdir -p "$LOGDIR"

echo "=== Chart Stale Scan — $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" >> "$LOGFILE"
chart stale 14 >> "$LOGFILE" 2>&1

# Count stale entries
STALE_COUNT=$(chart stale 14 2>/dev/null | grep -c "^  STALE" || echo "0")
echo "  Stale count: $STALE_COUNT" >> "$LOGFILE"
