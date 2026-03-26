#!/usr/bin/env bash
# reactor-reaper.sh — Reap stuck jobs, handoffs, and stale tasks
# Intent: Resilient [I08], Observable [I13].
# Runs every 6 hours. Moves stuck states to failed, logs, alerts.

set -eo pipefail

COMPOSE_DIR="/root/openclaw"
LOG="/root/.openclaw/logs/reaper.log"
mkdir -p "$(dirname "$LOG")"

_exec() {
  docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway "$@" 2>&1 | grep -v "level=warning"
}

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

echo "[$(ts)] Reaper started" >> "$LOG"

# 1. Reap stuck reactor-ledger jobs (chunked >24h → failed)
LEDGER="/home/node/.openclaw/bridge/reactor-ledger.sqlite"
STUCK_JOBS=$(_exec sqlite3 "$LEDGER" "
  UPDATE jobs SET status = 'failed'
  WHERE status = 'chunked'
  AND updated_at < datetime('now', '-24 hours');
  SELECT changes();
" 2>/dev/null) || STUCK_JOBS=0
[ "$STUCK_JOBS" -gt 0 ] && echo "[$(ts)] Reaped $STUCK_JOBS stuck chunked jobs" >> "$LOG"

# 2. Reap stuck handoffs (required >24h → failed)
STUCK_HANDOFFS=$(_exec sqlite3 "$LEDGER" "
  UPDATE handoff_sent SET handoff_state = 'failed'
  WHERE handoff_state = 'required'
  AND created_at < datetime('now', '-24 hours');
  SELECT changes();
" 2>/dev/null) || STUCK_HANDOFFS=0
[ "$STUCK_HANDOFFS" -gt 0 ] && echo "[$(ts)] Reaped $STUCK_HANDOFFS stuck handoffs" >> "$LOG"

# 3. Reap stuck ops.db tasks (pending >48h → failed)
OPS_DB="/home/node/.openclaw/ops.db"
STUCK_TASKS=$(_exec sqlite3 "$OPS_DB" "
  UPDATE tasks SET status = 'failed', updated_at = datetime('now')
  WHERE status = 'pending'
  AND created_at < datetime('now', '-48 hours');
  SELECT changes();
" 2>/dev/null) || STUCK_TASKS=0
[ "$STUCK_TASKS" -gt 0 ] && echo "[$(ts)] Reaped $STUCK_TASKS stuck ops.db tasks" >> "$LOG"

# 4. Cleanup expired agent_results (TTL 48h)
EXPIRED=$(_exec sqlite3 "$OPS_DB" "
  DELETE FROM agent_results
  WHERE consumed = 1
  AND consumed_at < datetime('now', '-48 hours');
  SELECT changes();
" 2>/dev/null) || EXPIRED=0
[ "$EXPIRED" -gt 0 ] && echo "[$(ts)] Cleaned $EXPIRED expired agent_results" >> "$LOG"

# 5. Cancel truth-gate retry chains (Fix: Fix: Fix:... blocked tasks)
HOST_OPS_DB="/root/.openclaw/ops.db"
RETRY_CHAINS=$(sqlite3 "$HOST_OPS_DB" "
  UPDATE tasks SET status = 'cancelled',
    outcome = COALESCE(outcome,'') || ' [auto-cancelled: retry chain depth exceeded]',
    updated_at = datetime('now')
  WHERE status = 'blocked' AND task LIKE 'Fix: Fix: Fix:%';
  SELECT changes();
" 2>/dev/null) || RETRY_CHAINS=0
[ "$RETRY_CHAINS" -gt 0 ] && echo "[$(ts)] Cancelled $RETRY_CHAINS truth-gate retry chains" >> "$LOG"

# 6. Age-out blocked tasks older than 24h (stuck beyond recovery)
AGED_BLOCKED=$(sqlite3 "$HOST_OPS_DB" "
  UPDATE tasks SET status = 'cancelled',
    outcome = COALESCE(outcome,'') || ' [auto-cancelled: blocked >24h]',
    updated_at = datetime('now')
  WHERE status = 'blocked'
  AND updated_at < datetime('now', '-24 hours');
  SELECT changes();
" 2>/dev/null) || AGED_BLOCKED=0
[ "$AGED_BLOCKED" -gt 0 ] && echo "[$(ts)] Aged out $AGED_BLOCKED blocked tasks (>24h)" >> "$LOG"

# 7. Unblock tasks whose dependencies were cancelled or failed (dead dependency chains)
UNBLOCKED=$(sqlite3 "$HOST_OPS_DB" "
  UPDATE tasks SET blocked_by = NULL, updated_at = datetime('now')
  WHERE status = 'pending'
  AND blocked_by IS NOT NULL
  AND blocked_by IN (SELECT CAST(id AS TEXT) FROM tasks WHERE status IN ('cancelled','failed'));
  SELECT changes();
" 2>/dev/null) || UNBLOCKED=0
[ "$UNBLOCKED" -gt 0 ] && echo "[$(ts)] Unblocked $UNBLOCKED tasks with cancelled/failed dependencies" >> "$LOG"

# 8. Auto-answer expired feedback questions with first option (interview pattern)
EXPIRED_FEEDBACK=$(sqlite3 "$HOST_OPS_DB" "
  UPDATE bearings_queue SET status='expired',
    response_value = json_extract(options, '$[0]'),
    answered_at = datetime('now'),
    approved_by = 'auto-timeout'
  WHERE status = 'pending'
  AND expires_at IS NOT NULL
  AND expires_at < datetime('now');
  SELECT changes();
" 2>/dev/null) || EXPIRED_FEEDBACK=0
[ "$EXPIRED_FEEDBACK" -gt 0 ] && echo "[$(ts)] Auto-answered $EXPIRED_FEEDBACK expired feedback questions" >> "$LOG"

TOTAL=$((STUCK_JOBS + STUCK_HANDOFFS + STUCK_TASKS + EXPIRED + RETRY_CHAINS + AGED_BLOCKED + EXPIRED_FEEDBACK))
if [ "$TOTAL" -gt 0 ]; then
  echo "[$(ts)] Reaper total actions: $TOTAL" >> "$LOG"
  mkdir -p /root/.openclaw/health
  echo "{\"ts\":\"$(ts)\",\"source\":\"reaper\",\"stuck_jobs\":$STUCK_JOBS,\"stuck_handoffs\":$STUCK_HANDOFFS,\"stuck_tasks\":$STUCK_TASKS,\"expired\":$EXPIRED}" >> /root/.openclaw/health/buffer.jsonl
  # Auto-log to issue tracker (zero tokens)
  [ "$STUCK_JOBS" -gt 0 ] && issue-log "Reaper: $STUCK_JOBS stuck chunked jobs moved to failed" --source reaper --severity medium 2>/dev/null || true
  [ "$STUCK_HANDOFFS" -gt 0 ] && issue-log "Reaper: $STUCK_HANDOFFS stuck handoffs moved to failed" --source reaper --severity medium 2>/dev/null || true
  [ "$STUCK_TASKS" -gt 0 ] && issue-log "Reaper: $STUCK_TASKS stuck ops.db tasks moved to failed" --source reaper --severity medium 2>/dev/null || true
fi

echo "[$(ts)] Reaper done" >> "$LOG"
