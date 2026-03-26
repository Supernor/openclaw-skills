#!/usr/bin/env bash
# workshop-submit.sh — Direct task creation fallback for ops.db
# Works even when gateway MCP is down.
#
# Usage:
#   workshop-submit.sh "task description" [agent] [urgency] [context]
#
# Examples:
#   workshop-submit.sh "Workshop Spark: Real-time agent dashboard"
#   workshop-submit.sh "Fix Bridge login" spec-dev blocking
#   workshop-submit.sh "Research competitor pricing" spec-research routine "For Macon pitch"

set -euo pipefail

TASK="${1:?Usage: workshop-submit.sh \"task\" [agent] [urgency] [context] [host_op] [routing_mode] [blocked_by]}"
AGENT="${2:-main}"
URGENCY="${3:-routine}"
CONTEXT="${4:-}"
HOST_OP="${5:-reactor-dispatch}"
ROUTING_MODE="${6:-direct}"
BLOCKED_BY="${7:-}"

# Captain = delegate mode by default
if [ "$AGENT" = "main" ] && [ "$ROUTING_MODE" = "direct" ]; then
  ROUTING_MODE="delegate"
fi

# Validate urgency
case "$URGENCY" in
  routine|blocking|critical) ;;
  *) echo "Error: urgency must be routine, blocking, or critical" >&2; exit 1 ;;
esac

# Find ops.db
OPS_DB="/root/.openclaw/ops.db"
if [ ! -f "$OPS_DB" ]; then
  OPS_DB="/home/node/.openclaw/ops.db"
fi
if [ ! -f "$OPS_DB" ]; then
  echo "Error: ops.db not found" >&2
  exit 1
fi

# Build meta JSON via Python (handles escaping properly — bash sed can't handle newlines in JSON)
META=$(python3 -c "
import json, sys
meta = json.dumps({
    'host_op': sys.argv[1],
    'agent': sys.argv[2],
    'prompt': sys.argv[3][:1500] + (' Context: ' + sys.argv[4] if sys.argv[4] else ''),
    'routing_mode': sys.argv[5],
    'telegram_chat_id': '8561305605',
})
print(meta)
" "$HOST_OP" "$AGENT" "$TASK" "$CONTEXT" "$ROUTING_MODE")

# Insert task with meta
TASK_ID=$(python3 -c "
import sqlite3, sys, json
db = sqlite3.connect(sys.argv[1])
db.execute(
    'INSERT INTO tasks (agent, urgency, status, task, context, meta, blocked_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
    (sys.argv[2], sys.argv[3], 'pending', sys.argv[4], sys.argv[5] or None, sys.argv[6], sys.argv[7] or None)
)
db.commit()
print(db.execute('SELECT last_insert_rowid()').fetchone()[0])
db.close()
" "$OPS_DB" "$AGENT" "$URGENCY" "$TASK" "$CONTEXT" "$META" "$BLOCKED_BY")

echo "Task #${TASK_ID} created [${AGENT}/${URGENCY}/${HOST_OP}]: ${TASK}"
