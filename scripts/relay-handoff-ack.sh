#!/usr/bin/env bash
# relay-handoff-ack.sh — Acknowledge a reactor handoff
# Called by Relay (or any agent) to confirm the user was notified.
# Stops the retry sweep from re-sending this handoff.
#
# Usage:
#   relay-handoff-ack.sh <task-id>
#   relay-handoff-ack.sh --list-unacked          # show unacked handoffs
#   relay-handoff-ack.sh --list-dlq              # show dead-lettered handoffs
#   relay-handoff-ack.sh --retry-dlq <task-id>   # retry a dead-lettered handoff
#   relay-handoff-ack.sh --ack-all               # ack everything (emergency)

set -eo pipefail

BASE="/home/node/.openclaw"
if [ ! -d "$BASE" ] && [ -d "/root/.openclaw" ]; then
  BASE="/root/.openclaw"
fi

LEDGER_DB="${BASE}/bridge/reactor-ledger.sqlite"

if [ ! -f "$LEDGER_DB" ]; then
  echo '{"error":"ledger not found","path":"'"$LEDGER_DB"'"}' >&2
  exit 1
fi

CMD="${1:?Usage: relay-handoff-ack.sh <task-id> | --list-unacked | --list-dlq | --retry-dlq <id> | --ack-all}"

case "$CMD" in
  --list-unacked)
    sqlite3 -json "$LEDGER_DB" "
      SELECT h.task_id, h.status, h.sent_at, h.retry_count, h.discord_sent,
             h.handoff_state, j.subject, j.channel_id
      FROM handoff_sent h
      LEFT JOIN jobs j ON h.task_id = j.task_id
      WHERE h.acked = 0
      ORDER BY h.sent_at DESC
      LIMIT 20;
    " 2>/dev/null || echo "[]"
    ;;

  --list-dlq)
    sqlite3 -json "$LEDGER_DB" "
      SELECT h.task_id, h.status, h.sent_at, h.handoff_attempts, h.handoff_last_error,
             h.handoff_updated_at, j.subject, j.channel_id
      FROM handoff_sent h
      LEFT JOIN jobs j ON h.task_id = j.task_id
      WHERE h.handoff_state = 'failed'
      ORDER BY h.handoff_updated_at DESC
      LIMIT 20;
    " 2>/dev/null || echo "[]"
    ;;

  --retry-dlq)
    DLQ_ID="${2:?Usage: relay-handoff-ack.sh --retry-dlq <task-id>}"
    SAFE_DLQ=$(echo "$DLQ_ID" | sed "s/'/''/g")
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Only retry if currently in 'failed' state
    CHANGES=$(sqlite3 "$LEDGER_DB" "
      UPDATE handoff_sent
      SET handoff_state = 'required', handoff_attempts = 0, retry_count = 0,
          handoff_last_error = NULL, handoff_updated_at = '$TS'
      WHERE task_id = '$SAFE_DLQ' AND handoff_state = 'failed';
      SELECT changes();
    " 2>/dev/null || echo "0")

    if [ "$CHANGES" = "1" ]; then
      echo "{\"status\":\"ok\",\"taskId\":\"$DLQ_ID\",\"action\":\"reset to required\",\"at\":\"$TS\"}"
    else
      echo "{\"error\":\"task not in DLQ or not found\",\"taskId\":\"$DLQ_ID\"}"
      exit 1
    fi
    ;;

  --ack-all)
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    COUNT=$(sqlite3 "$LEDGER_DB" "
      UPDATE handoff_sent SET acked=1, acked_at='$TS' WHERE acked=0;
      SELECT changes();
    " 2>/dev/null || echo "0")
    sqlite3 "$LEDGER_DB" "
      UPDATE jobs SET relay_handoff_acked=1, relay_handoff_ack_at='$TS'
      WHERE relay_handoff_sent=1 AND relay_handoff_acked=0;
    " 2>/dev/null || true
    echo "{\"status\":\"ok\",\"acked\":$COUNT,\"at\":\"$TS\"}"
    ;;

  *)
    TASK_ID="$CMD"
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    SAFE_ID=$(echo "$TASK_ID" | sed "s/'/''/g")

    # Check if exists
    EXISTS=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM handoff_sent WHERE task_id='$SAFE_ID';" 2>/dev/null || echo "0")
    if [ "$EXISTS" = "0" ]; then
      echo "{\"error\":\"task not found in handoff_sent\",\"taskId\":\"$TASK_ID\"}"
      exit 1
    fi

    sqlite3 "$LEDGER_DB" "
      UPDATE handoff_sent SET acked=1, acked_at='$TS' WHERE task_id='$SAFE_ID';
      UPDATE jobs SET relay_handoff_acked=1, relay_handoff_ack_at='$TS' WHERE task_id='$SAFE_ID';
    " 2>/dev/null

    echo "{\"status\":\"ok\",\"taskId\":\"$TASK_ID\",\"acked_at\":\"$TS\"}"
    ;;
esac
