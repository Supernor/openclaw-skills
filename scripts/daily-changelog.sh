#!/usr/bin/env bash
# Alignment: morning cron that charts the last 24h of agent and task activity.
# Role: summarize overnight OpenClaw work into one `changelog` Chartroom entry.
# Dependencies: reads ops.db task outcomes from the last 24 hours, calls the
# `chart` CLI for read/add operations, and appends execution notes to
# /root/.openclaw/logs/daily-changelog.log.
# Key patterns: idempotent daily registration via `changelog-auto-YYYY-MM-DD`,
# UTC date windows for stable cron output, and changelog-only write behavior so
# downstream readers can query a single daily summary without mutating task state.
# Reference: /root/.openclaw/docs/policy-context-injection.md

set -eo pipefail

CHART="/usr/local/bin/chart"
OPS_DB="/root/.openclaw/ops.db"
DATE=$(date -u +%Y-%m-%d)
YESTERDAY=$(date -u -d "yesterday" +%Y-%m-%d 2>/dev/null || date -u -v-1d +%Y-%m-%d 2>/dev/null)
CHART_ID="changelog-auto-${DATE}"
LOG="/root/.openclaw/logs/daily-changelog.log"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >> "$LOG"; }

# Check if today's changelog already exists (idempotent)
EXISTING=$($CHART read "$CHART_ID" 2>/dev/null | head -1 || true)
if echo "$EXISTING" | grep -q "ID:" 2>/dev/null; then
    log "Changelog $CHART_ID already exists, skipping"
    exit 0
fi

# Gather completed tasks from the last 24 hours
COMPLETED=$(sqlite3 "$OPS_DB" "
    SELECT agent, substr(task,1,80), duration_ms
    FROM tasks
    WHERE status='completed'
    AND REPLACE(REPLACE(completed_at,'T',' '),'Z','') > datetime('now', '-24 hours')
    ORDER BY completed_at
" 2>/dev/null)

COMPLETED_COUNT=$(echo "$COMPLETED" | grep -c "." 2>/dev/null || echo "0")

# Gather blocked tasks (problems found)
BLOCKED=$(sqlite3 "$OPS_DB" "
    SELECT agent, substr(task,1,60), substr(outcome,1,60)
    FROM tasks
    WHERE status='blocked'
    AND REPLACE(REPLACE(created_at,'T',' '),'Z','') > datetime('now', '-24 hours')
    ORDER BY created_at
" 2>/dev/null)

BLOCKED_COUNT=$(echo "$BLOCKED" | grep -c "." 2>/dev/null || echo "0")

# Gather new issues logged
ISSUES=$(sqlite3 "$OPS_DB" "
    SELECT system, severity, substr(description,1,60)
    FROM issues
    WHERE REPLACE(REPLACE(logged_at,'T',' '),'Z','') > datetime('now', '-24 hours')
    ORDER BY logged_at
" 2>/dev/null)

ISSUE_COUNT=$(echo "$ISSUES" | grep -c "." 2>/dev/null || echo "0")

# Build the changelog text
SUMMARY="AUTO CHANGELOG ${DATE}. ${COMPLETED_COUNT} tasks completed, ${BLOCKED_COUNT} blocked, ${ISSUE_COUNT} issues logged."

# Add agent breakdown
AGENT_SUMMARY=$(sqlite3 "$OPS_DB" "
    SELECT agent, COUNT(*) as cnt
    FROM tasks
    WHERE status='completed'
    AND REPLACE(REPLACE(completed_at,'T',' '),'Z','') > datetime('now', '-24 hours')
    GROUP BY agent ORDER BY cnt DESC
" 2>/dev/null | head -8 | while IFS='|' read AGENT CNT; do
    echo "$AGENT($CNT)"
done | tr '\n' ' ')

SUMMARY="$SUMMARY Agents: $AGENT_SUMMARY"

# Add blocked summary if any
if [ "$BLOCKED_COUNT" -gt 0 ]; then
    BLOCK_AGENTS=$(sqlite3 "$OPS_DB" "
        SELECT agent, COUNT(*) FROM tasks
        WHERE status='blocked' AND REPLACE(REPLACE(created_at,'T',' '),'Z','') > datetime('now', '-24 hours')
        GROUP BY agent
    " 2>/dev/null | head -5 | while IFS='|' read A C; do echo "$A($C)"; done | tr '\n' ' ')
    SUMMARY="$SUMMARY Blocked: $BLOCK_AGENTS"
fi

# Truncate to chart limit
SUMMARY=$(echo "$SUMMARY" | head -c 1900)

# Create the chart
$CHART add "$CHART_ID" "$SUMMARY" changelog 0.7 >> "$LOG" 2>&1

log "Created $CHART_ID: $COMPLETED_COUNT completed, $BLOCKED_COUNT blocked, $ISSUE_COUNT issues"
echo "Changelog $CHART_ID created"
