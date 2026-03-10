#!/usr/bin/env bash
# workspace-freshness-cron.sh — Weekly workspace freshness check (cron wrapper).
# Intent: Observable [I13]. Owner: Quartermaster (spec-quartermaster).
# Runs workspace-freshness-scanner.py and logs results.

set -eo pipefail

SCRIPT="/root/.openclaw/scripts/workspace-freshness-scanner.py"
LOGDIR="/root/.openclaw/logs"
LOGFILE="$LOGDIR/workspace-freshness.log"

mkdir -p "$LOGDIR"

echo "=== Workspace Freshness Scan — $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" >> "$LOGFILE"
python3 "$SCRIPT" --stale-only >> "$LOGFILE" 2>&1

# If critical issues found, chart them
CRITICAL=$(python3 "$SCRIPT" --json 2>/dev/null | jq '[.results[] | select(.freshness_score < 4)] | length' 2>/dev/null || echo "0")
if [ "$CRITICAL" -gt 0 ]; then
  chart add issue "issue-workspace-freshness-$(date +%Y%m%d)" \
    "$CRITICAL agents have critically stale workspaces. Run workspace-freshness-scanner.py for details. Intent Observable I13. Discovered $(date +%Y-%m-%d)." 2>/dev/null || true
fi
