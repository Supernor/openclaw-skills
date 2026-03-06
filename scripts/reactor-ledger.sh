#!/usr/bin/env bash
# reactor-ledger.sh — Query helper for the Reactor job ledger
# Usage:
#   reactor-ledger.sh status          — counts by status
#   reactor-ledger.sh recent [N]      — last N jobs (default 10)
#   reactor-ledger.sh task <task-id>  — full detail for one job
#   reactor-ledger.sh open-questions  — unanswered questions
#   reactor-ledger.sh events <task-id> — event timeline for a job
#   reactor-ledger.sh retros [N]      — recent retros

set -eo pipefail

DB="/home/node/.openclaw/bridge/reactor-ledger.sqlite"
if [ ! -f "$DB" ] && [ -f "/root/.openclaw/bridge/reactor-ledger.sqlite" ]; then
  DB="/root/.openclaw/bridge/reactor-ledger.sqlite"
fi

if [ ! -f "$DB" ]; then
  echo "Ledger DB not found at $DB" >&2
  exit 1
fi

sql() {
  sqlite3 -header -column "$DB" "$@"
}

sql_csv() {
  sqlite3 -header -csv "$DB" "$@"
}

case "${1:-help}" in
  status)
    echo "=== Job Status Summary ==="
    sql "SELECT status, COUNT(*) as count, ROUND(AVG(duration_seconds),1) as avg_duration_s, SUM(tool_count) as total_tools FROM jobs GROUP BY status ORDER BY count DESC;"
    echo ""
    echo "=== Total ==="
    sql "SELECT COUNT(*) as total_jobs, SUM(duration_seconds) as total_seconds, SUM(tool_count) as total_tools FROM jobs;"
    ;;

  recent)
    local_n="${2:-10}"
    echo "=== Last ${local_n} Jobs ==="
    sql "SELECT task_id, subject, status, duration_seconds as dur_s, tool_count as tools, date_received FROM jobs ORDER BY date_received DESC LIMIT ${local_n};"
    ;;

  task)
    if [ -z "${2:-}" ]; then
      echo "Usage: reactor-ledger.sh task <task-id>" >&2
      exit 1
    fi
    task_id="$2"
    echo "=== Job Detail: ${task_id} ==="
    sql "SELECT * FROM jobs WHERE task_id='${task_id}';"
    echo ""
    echo "=== Events ==="
    sql "SELECT event_type, ts, payload_json FROM events WHERE task_id='${task_id}' ORDER BY ts;"
    echo ""
    echo "=== Questions ==="
    sql "SELECT id, question_text, to_role, answered, created_at FROM questions WHERE task_id='${task_id}';"
    echo ""
    echo "=== Feedback ==="
    sql "SELECT id, feedback_to_openclaw, created_at FROM feedback WHERE task_id='${task_id}';"
    echo ""
    echo "=== Retros ==="
    sql "SELECT id, wins, losses, learnings, created_at FROM retros WHERE task_id='${task_id}';"
    ;;

  events)
    if [ -z "${2:-}" ]; then
      echo "Usage: reactor-ledger.sh events <task-id>" >&2
      exit 1
    fi
    sql "SELECT event_type, ts, payload_json FROM events WHERE task_id='${2}' ORDER BY ts;"
    ;;

  open-questions)
    echo "=== Open Questions ==="
    sql "SELECT q.id, q.task_id, j.subject, q.question_text, q.to_role, q.created_at FROM questions q LEFT JOIN jobs j ON q.task_id = j.task_id WHERE q.answered = 0 ORDER BY q.created_at DESC;"
    ;;

  retros)
    local_n="${2:-10}"
    echo "=== Recent Retros ==="
    sql "SELECT r.task_id, j.subject, r.wins, r.losses, r.learnings, r.created_at FROM retros r LEFT JOIN jobs j ON r.task_id = j.task_id ORDER BY r.created_at DESC LIMIT ${local_n};"
    ;;

  lockstep)
    echo "=== Lockstep Verification ==="
    sql "SELECT j.task_id, j.status AS job_status, j.relay_handoff_required AS rhr, j.relay_handoff_sent AS rhs, h.task_id IS NOT NULL AS in_dedup, h.bus_id, CASE WHEN j.relay_handoff_required=1 AND j.relay_handoff_sent=1 AND h.task_id IS NOT NULL THEN 'LOCKSTEP_OK' WHEN j.relay_handoff_required=1 AND j.relay_handoff_sent=0 THEN 'HANDOFF_PENDING' WHEN j.relay_handoff_required=0 AND j.status IN ('pending','in-progress') THEN 'IN_FLIGHT' ELSE 'MISMATCH' END AS lockstep FROM jobs j LEFT JOIN handoff_sent h ON j.task_id=h.task_id ORDER BY j.date_received DESC;"
    ;;

  handoff)
    echo "=== Handoff Artifact Verification ==="
    OUTBOX="/root/.openclaw/bridge/outbox"
    sql "SELECT j.task_id, j.status AS job_status, j.relay_handoff_required AS rhr, j.relay_handoff_sent AS rhs FROM jobs j ORDER BY j.date_received DESC;" | while IFS='|' read -r line; do
      echo "$line"
    done
    echo ""
    echo "--- Handoff files in outbox ---"
    for hf in "$OUTBOX"/*-handoff.json; do
      [ -f "$hf" ] || { echo "(none found)"; break; }
      tid=$(jq -r '.task_id' "$hf" 2>/dev/null)
      st=$(jq -r '.status' "$hf" 2>/dev/null)
      na=$(jq -r '.next_action' "$hf" 2>/dev/null)
      echo "  ${tid}: status=${st}, next_action=${na}"
    done
    ;;

  full-check)
    if [ -z "${2:-}" ]; then
      echo "Usage: reactor-ledger.sh full-check <task-id>" >&2
      exit 1
    fi
    task_id="$2"
    OUTBOX="/root/.openclaw/bridge/outbox"
    EVENTS_FILE="/root/.openclaw/bridge/events/reactor.jsonl"
    echo "=== Full Check: ${task_id} ==="
    echo ""
    echo "1) SQL row:"
    sql "SELECT task_id, status, relay_handoff_required, relay_handoff_sent FROM jobs WHERE task_id='${task_id}';"
    echo ""
    echo "2) JSONL terminal event:"
    grep "\"taskId\":\"${task_id}\"" "$EVENTS_FILE" 2>/dev/null | grep '"relay_handoff_required":true' | tail -1 || echo "  (not found)"
    echo ""
    echo "3) Outbox result:"
    [ -f "${OUTBOX}/${task_id}-result.json" ] && echo "  EXISTS: ${OUTBOX}/${task_id}-result.json" || echo "  MISSING"
    echo ""
    echo "4) Outbox handoff artifact:"
    [ -f "${OUTBOX}/${task_id}-handoff.json" ] && { echo "  EXISTS: ${OUTBOX}/${task_id}-handoff.json"; jq -c '.' "${OUTBOX}/${task_id}-handoff.json" 2>/dev/null; } || echo "  MISSING"
    echo ""
    echo "5) Bus handoff marker (dedup table):"
    sql "SELECT task_id, status, sent_at, bus_id FROM handoff_sent WHERE task_id='${task_id}';"
    echo ""
    # Verdict
    local_sql_ok=$(sqlite3 "$DB" "SELECT COUNT(*) FROM jobs WHERE task_id='${task_id}' AND relay_handoff_required=1;" 2>/dev/null || echo 0)
    local_jsonl_ok=$(grep -c "\"taskId\":\"${task_id}\".*relay_handoff_required.*true" "$EVENTS_FILE" 2>/dev/null || echo 0)
    local_result_ok=0; [ -f "${OUTBOX}/${task_id}-result.json" ] && local_result_ok=1
    local_handoff_ok=0; [ -f "${OUTBOX}/${task_id}-handoff.json" ] && local_handoff_ok=1
    local_bus_ok=$(sqlite3 "$DB" "SELECT COUNT(*) FROM handoff_sent WHERE task_id='${task_id}';" 2>/dev/null || echo 0)
    total=$((local_sql_ok + (local_jsonl_ok > 0 ? 1 : 0) + local_result_ok + local_handoff_ok + (local_bus_ok > 0 ? 1 : 0)))
    echo "VERDICT: ${total}/5 stores present"
    [ "$total" -eq 5 ] && echo "STATUS: ALL_CLEAR" || echo "STATUS: INCOMPLETE (${total}/5)"
    ;;

  help|*)
    echo "reactor-ledger.sh — Reactor job ledger query tool"
    echo ""
    echo "Commands:"
    echo "  status              Counts by status + averages"
    echo "  recent [N]          Last N jobs (default 10)"
    echo "  task <task-id>      Full detail for one job"
    echo "  events <task-id>    Event timeline for a job"
    echo "  open-questions      Unanswered questions"
    echo "  retros [N]          Recent retros"
    echo "  lockstep            Verify SQL/JSONL/handoff agreement"
    echo "  handoff             List handoff artifacts"
    echo "  full-check <id>     5-store verification for a task"
    ;;
esac
