#!/usr/bin/env bash
# issue-pipeline-tick.sh — Runs every 10 minutes via cron.
# Checks for unbundled issues and bundles them by fingerprint.
# Also checks for critical severity issues that need immediate Telegram alert.
#
# Part of the boy scout issue pipeline:
# discover → BATCH (this script) → propose → debate → execute → close
#
# Cadence: 10-min rolling window OR 5+ unbundled issues (whichever first).
# The cron runs every 10 min; the threshold check below handles the count trigger.

set -eo pipefail

LOG="/root/.openclaw/logs/issue-pipeline.log"
ISSUE_LOG="/root/.openclaw/scripts/issue-log.py"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >> "$LOG"; }

# Count unbundled issues
UNBUNDLED=$(sqlite3 /root/.openclaw/ops.db "SELECT COUNT(*) FROM issues WHERE bundle_id IS NULL AND status='logged'" 2>/dev/null || echo 0)

# Only bundle if there are unbundled issues — but ALWAYS run orphan escalation and blocked diagnosis below
if [ "$UNBUNDLED" -gt 0 ]; then
    log "Pipeline tick: $UNBUNDLED unbundled issues"

# Check for critical severity — immediate Telegram alert, no batching
CRITICAL=$(sqlite3 /root/.openclaw/ops.db "SELECT id, description, system FROM issues WHERE severity='critical' AND status='logged' AND bundle_id IS NULL LIMIT 1" 2>/dev/null)
if [ -n "$CRITICAL" ]; then
    CHAT_ID="8561305605"  # Robert's Telegram
    BOT_TOKEN="${TELEGRAM_BOT_TOKEN_ROBERT:-${TELEGRAM_BOT_TOKEN}}"
    if [ -n "$BOT_TOKEN" ]; then
        MSG="CRITICAL issue logged: $CRITICAL"
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" -d "text=${MSG:0:200}" -d "parse_mode=HTML" > /dev/null 2>&1 || true
        log "Critical alert sent to Telegram"
    fi
fi

# Bundle if 1+ unbundled (10-min window already passed since cron interval)
python3 "$ISSUE_LOG" bundle >> "$LOG" 2>&1
log "Bundling complete"

# Check oscillation: 3+ fixes to same system in 48h = warning
OSCILLATING=$(sqlite3 /root/.openclaw/ops.db "
    SELECT system, COUNT(*) as fixes FROM issues
    WHERE status='fixed' AND updated_at > datetime('now', '-48 hours')
    GROUP BY system HAVING fixes >= 3
" 2>/dev/null)
if [ -n "$OSCILLATING" ]; then
    log "OSCILLATION WARNING: $OSCILLATING"
fi

fi  # end of UNBUNDLED > 0 block

# ── These safety checks run EVERY tick, regardless of unbundled count ──

# ── Layer 3: Auto-escalate orphaned pending tasks ──
# Tasks pending >2 hours without host_op can't be picked up by executor.
# Add reactor-dispatch so they don't starve.
ORPHANS=$(sqlite3 /root/.openclaw/ops.db "
    SELECT id FROM tasks
    WHERE status='pending'
    AND (meta IS NULL OR json_extract(meta, '\$.host_op') IS NULL)
    AND REPLACE(created_at, 'Z', '') < datetime('now', '-2 hours')
" 2>/dev/null)
if [ -n "$ORPHANS" ]; then
    for TASK_ID in $ORPHANS; do
        sqlite3 /root/.openclaw/ops.db "
            UPDATE tasks SET meta = json_set(COALESCE(meta, '{}'), '\$.host_op', 'reactor-dispatch'),
                             updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
            WHERE id = $TASK_ID AND status = 'pending'
        " 2>/dev/null
        log "Auto-escalated orphaned task #$TASK_ID (pending >2h, no host_op)"
    done
fi

# ── Blocked task auto-diagnosis ──
# Check blocked tasks for fixable infrastructure causes
BLOCKED_READONLY=$(sqlite3 /root/.openclaw/ops.db "
    SELECT id, outcome FROM tasks
    WHERE status='blocked' AND (outcome LIKE '%readonly%' OR outcome LIKE '%read-only%' OR outcome LIKE '%permission denied%')
    AND updated_at > datetime('now', '-24 hours')
    LIMIT 3
" 2>/dev/null)
if [ -n "$BLOCKED_READONLY" ]; then
    # Auto-fix common readonly databases
    for DB_FILE in /root/.openclaw/transcripts.db /root/.openclaw/ops.db; do
        PERMS=$(stat -c %a "$DB_FILE" 2>/dev/null)
        if [ "$PERMS" = "644" ]; then
            chmod 666 "$DB_FILE" 2>/dev/null
            log "Auto-fixed readonly: $DB_FILE ($PERMS → 666)"
        fi
    done
fi
