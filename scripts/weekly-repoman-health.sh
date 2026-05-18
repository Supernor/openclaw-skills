#!/usr/bin/env bash
# weekly-repoman-health.sh — Weekly health check dispatch for Repo-Man (spec-github)
#
# WHO:  Runs as cron job, dispatches work to spec-github agent
# WHAT: Creates a task for spec-github to run repo-health.sh and key-drift-check.sh
#        to verify GitHub repos are fresh and all required keys are present
# WHEN: Sunday 4:00am UTC — weekly, before the Monday agent schedule kicks in
# WHY:  Repos can drift silently (stale pushes, missing keys after .env edits).
#        Weekly verification catches drift before it becomes an incident.
#        Separate from nightly backup-push: this is a health CHECK, not a push.
# HOW:  1. Check concurrency (don't dispatch if VPS is overloaded)
#        2. INSERT a pending task for spec-github with both checks
#        3. Task runner picks it up and executes via host_op=codex-run
#
# DEPENDENCIES:
#   - /root/.openclaw/scripts/repo-health.sh (verifies repos are fresh)
#   - /root/.openclaw/scripts/key-drift-check.sh (verifies keys are present)
#   - ops.db tasks table
#   - cron-wrapper.sh wraps this for outcome tracking
#   - flock on /tmp/cron-weekly-repoman-health.lock prevents overlapping runs
#
# TROUBLESHOOTING:
#   IF NO TASK CREATED: Check concurrency cap or load.
#     DO THIS: sqlite3 /root/.openclaw/ops.db "SELECT COUNT(*) FROM tasks WHERE status='in_progress'"
#   IF HEALTH CHECK FAILS: Run the scripts directly to see what's wrong.
#     DO THIS: bash /root/.openclaw/scripts/repo-health.sh
#     DO THIS: bash /root/.openclaw/scripts/key-drift-check.sh
#   IF TASK STUCK: Check task-runner is alive.
#     VERIFY: systemctl status openclaw-task-runner

set -euo pipefail

# --- Config ---
OPS_DB="/root/.openclaw/ops.db"
LOG="/root/.openclaw/logs/weekly-repoman-health.log"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TODAY=$(date -u +%Y-%m-%d)
ROBERT_CHAT_ID="8561305605"

log() { echo "${TS} $1" >> "$LOG"; echo "$1"; }

mkdir -p "$(dirname "$LOG")"

# --- Step 1: Basic load check ---
# Don't dispatch if VPS is already overloaded
IN_PROGRESS=$(sqlite3 "$OPS_DB" "PRAGMA busy_timeout=5000; SELECT COUNT(*) FROM tasks WHERE status='in_progress'" | tail -1)
if [ "${IN_PROGRESS:-0}" -ge 2 ]; then
    log "SKIP: Concurrency cap reached (${IN_PROGRESS} tasks in progress). Will retry next week."
    log "  If this keeps happening, check what's running: sqlite3 $OPS_DB \"SELECT id,agent,task FROM tasks WHERE status='in_progress'\""
    exit 0
fi

# --- Step 2: Check for duplicate dispatch this week ---
# Prevent duplicate if script runs twice (manual + cron)
WEEK_START=$(date -u -d "last Sunday" +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u +%Y-%m-%dT00:00:00Z)
EXISTING=$(sqlite3 "$OPS_DB" "
    PRAGMA busy_timeout=5000;
    SELECT COUNT(*) FROM tasks
    WHERE agent='spec-github'
      AND task LIKE '%Weekly health%'
      AND created_at >= '${WEEK_START}'
      AND status NOT IN ('cancelled');
" | tail -1)

if [ "${EXISTING:-0}" -gt 0 ]; then
    log "SKIP: Weekly health task already dispatched this week (${EXISTING} found). No duplicate."
    exit 0
fi

# --- Step 3: Insert task for spec-github ---
TASK_DESC="Weekly health check: verify repos and keys"
CONTEXT="Triggered by weekly-repoman-health.sh (Sunday ${TODAY}). Run both repo-health and key-drift-check."
PROMPT="Run the weekly Repo-Man health check: 1) Execute /root/.openclaw/scripts/repo-health.sh — verify all 3 GitHub repos (openclaw-config, openclaw-workspace, openclaw-skills) exist and have recent pushes. 2) Execute /root/.openclaw/scripts/key-drift-check.sh — verify all required .env keys are present. Report: repo freshness (days since last push), key count (present/expected), any drift or missing items. If anything is stale (>7 days) or missing, flag it clearly. IMPORTANT: After completing, append a line to /root/.openclaw/workspace-spec-github/LAST_RUN.md in format: TIMESTAMP | weekly-health | PASS/FAIL | summary"
META=$(cat <<METAEOF
{"host_op":"codex-run","agent":"spec-github","nightly":false,"timeout":600,"prompt":"${PROMPT}","telegram_chat_id":"${ROBERT_CHAT_ID}"}
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
        'weekly-repoman-health.sh'
    );
    SELECT last_insert_rowid();
" | tail -1)
log "Task #${TASK_ID} created for spec-github: ${TASK_DESC}"
echo "RESULT_LABEL: dispatched"
