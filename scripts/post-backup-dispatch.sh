#!/usr/bin/env bash
# post-backup-dispatch.sh — Trigger Repo-Man (spec-github) after successful nightly backup
#
# WHO:  Runs as cron job, dispatches work to spec-github agent
# WHAT: Checks nightly-backup.log for success marker, inserts a task into ops.db
#        for spec-github to push backups to GitHub via the backup-suite skill
# WHEN: 3:30am UTC daily — 30 minutes after nightly-backup.sh (3am UTC)
# WHY:  Backups are only useful if they reach offsite storage. This wiring
#        automates the nightly-backup → GitHub-push pipeline so no human
#        intervention is needed. If the backup failed, we don't push garbage.
# HOW:  1. Grep today's backup log for "Nightly backup finished"
#        2. If found: INSERT a pending task for spec-github with host_op=codex-run
#        3. If not found: log the skip (cron-alert already handles backup failures)
#
# DEPENDENCIES:
#   - /root/.openclaw/scripts/nightly-backup.sh must run before this (3am UTC)
#   - /root/.openclaw/logs/nightly-backup.log must exist
#   - ops.db tasks table (see schema: agent, urgency, status, task, context, meta, created_by)
#   - cron-wrapper.sh wraps this for outcome tracking in cron_outcomes
#   - flock on /tmp/cron-post-backup-dispatch.lock prevents overlapping runs
#
# TROUBLESHOOTING:
#   IF NO TASK CREATED: Check nightly-backup.log for today's date + success marker.
#     DO THIS: grep "$(date -u +%Y-%m-%d)" /root/.openclaw/logs/nightly-backup.log | grep "Nightly backup finished"
#   IF TASK STUCK PENDING: Check task-runner is running (systemctl status openclaw-task-runner).
#     VERIFY: sqlite3 /root/.openclaw/ops.db "SELECT id,status,task FROM tasks WHERE agent='spec-github' ORDER BY id DESC LIMIT 3"
#   IF SQLITE LOCKED: Another process has the DB. The PRAGMA busy_timeout=5000 should handle it.
#     LAST FIX: Increase busy_timeout or check for long-running queries.

set -euo pipefail

# --- Config ---
OPS_DB="/root/.openclaw/ops.db"
BACKUP_LOG="/root/.openclaw/logs/nightly-backup.log"
LOG="/root/.openclaw/logs/post-backup-dispatch.log"
TODAY=$(date -u +%Y-%m-%d)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ROBERT_CHAT_ID="8561305605"

log() { echo "${TS} $1" >> "$LOG"; echo "$1"; }

mkdir -p "$(dirname "$LOG")"

# --- Step 1: Check if tonight's backup succeeded ---
# The success marker is the literal string "Nightly backup finished" written by nightly-backup.sh line 88.
# We grep for today's date AND the marker to avoid matching old logs.
if ! grep -q "${TODAY}.*Nightly backup finished\|Nightly backup finished.*${TODAY}" "$BACKUP_LOG" 2>/dev/null; then
    # Also try: marker on today's date entries (log format: 2026-05-18T03:00:15Z Nightly backup finished...)
    TODAYS_LINES=$(grep "^${TODAY}" "$BACKUP_LOG" 2>/dev/null || true)
    if ! echo "$TODAYS_LINES" | grep -q "Nightly backup finished"; then
        log "SKIP: No successful backup found for ${TODAY}. cron-alert handles backup failures."
        log "  Checked: ${BACKUP_LOG} for '${TODAY}' + 'Nightly backup finished'"
        log "  This is normal if the backup hasn't run yet or if it failed."
        exit 0
    fi
fi

log "Backup succeeded for ${TODAY}. Dispatching spec-github backup-suite."

# --- Step 2: Check if a backup-push task was already dispatched today ---
# Prevents duplicate tasks if this script runs twice (e.g., manual + cron)
EXISTING=$(sqlite3 "$OPS_DB" "
    PRAGMA busy_timeout=5000;
    SELECT COUNT(*) FROM tasks
    WHERE agent='spec-github'
      AND task LIKE '%backup-suite%'
      AND created_at >= '${TODAY}T00:00:00Z'
      AND status NOT IN ('cancelled');
" | tail -1)

if [ "${EXISTING:-0}" -gt 0 ]; then
    log "SKIP: Backup-suite task already dispatched today (${EXISTING} found). No duplicate."
    exit 0
fi

# --- Step 3: Insert task for spec-github ---
# host_op=backup-suite: golden script that runs all 3 backups + repo-health.
# Zero tokens — no LLM needed. Always works regardless of Codex/model health.
# Previous approach used codex-run which failed when Codex was degraded.
# Changed to golden script 2026-05-18 for reliability.
TASK_DESC="Nightly backup-suite: Push ${TODAY} backup to GitHub repos"
CONTEXT="Triggered by post-backup-dispatch.sh after successful nightly backup. Backup dir: /root/.openclaw/backups/${TODAY}"
META=$(cat <<METAEOF
{"host_op":"backup-suite","agent":"spec-github","nightly":true,"timeout":300}
METAEOF
)

# INSERT + last_insert_rowid in ONE sqlite3 call (separate calls get rowid=0)
TASK_ID=$(sqlite3 "$OPS_DB" "
    PRAGMA busy_timeout=5000;
    INSERT INTO tasks (agent, urgency, status, task, context, meta, created_by)
    VALUES (
        'spec-github',
        'routine',
        'pending',
        '${TASK_DESC}',
        '${CONTEXT}',
        '$(echo "$META" | tr "'" "_")',
        'post-backup-dispatch.sh'
    );
    SELECT last_insert_rowid();
" | tail -1)
log "Task #${TASK_ID} created for spec-github: ${TASK_DESC}"
echo "RESULT_LABEL: dispatched"
