#!/usr/bin/env bash
# workshop-submit.sh — Direct task creation fallback for ops.db
# Works even when gateway MCP is down.
#
# Usage:
#   workshop-submit.sh "task description" [agent] [urgency] [context] [host_op] [routing_mode] [blocked_by] [timeout_s] [project_id]
#
# Examples:
#   workshop-submit.sh "Workshop Intake: Real-time agent dashboard"
#   workshop-submit.sh "Fix Bridge login" spec-dev blocking
#   workshop-submit.sh "Research competitor pricing" spec-research routine "For Macon pitch"

set -euo pipefail

TASK="${1:?Usage: workshop-submit.sh \"task\" [agent] [urgency] [context] [host_op] [routing_mode] [blocked_by] [timeout_s]}"
AGENT="${2:-main}"
URGENCY="${3:-routine}"
CONTEXT="${4:-}"
HOST_OP="${5:-reactor-dispatch}"
ROUTING_MODE="${6:-direct}"
BLOCKED_BY="${7:-}"
TIMEOUT_S="${8:-}"   # optional stall-ceiling seconds for engine ops (codex/claude reason silently >180s)
PROJECT_ID="${9:-}"  # optional ops.db projects.id — links this task to a Workshop project for rollup

# Captain = delegate mode by default
if [ "$AGENT" = "main" ] && [ "$ROUTING_MODE" = "direct" ]; then
  ROUTING_MODE="delegate"
fi

# Validate urgency
case "$URGENCY" in
  routine|blocking|critical) ;;
  *) echo "Error: urgency must be routine, blocking, or critical" >&2; exit 1 ;;
esac

# Validate host_op against known handlers
# WHY: Invalid host_ops create tasks that block forever with "Unknown host operation" error.
# DO THIS: Use one of the valid ops listed below.
# VERIFY: grep -c "\"$HOST_OP\"" /root/.openclaw/scripts/host-ops-executor.py
# Keep in sync with host-ops-executor.py "Registered operations" startup log line.
# (Stale list rejected claude-code-run etc. until 2026-06-11.)
VALID_OPS="bridge-edit bridge-style codex-reauth codex-reauth-telegram codex-run claude-code-run deploy-preview deploy-production discord-button eoin-escalate error-audit gateway-health gateway-restart gauntlet-design-review gauntlet-run gemini-run gemini-search generate-comp github-cli infra-audit lighthouse loop-redirect pool-fuel pool-status post-update-verify reactor-dispatch reactor-execute reactor-plan reactor-status reactor-stop reactor-undo relay-escalate scaffold-site screenshot session-transcript stitch-mockup sync-codex-auth sync-secrets system-health system-observe system-self-test workspace-cli backup-suite openclaw-update"
VALID=false
for op in $VALID_OPS; do
  if [ "$HOST_OP" = "$op" ]; then VALID=true; break; fi
done
if ! $VALID; then
  echo "ERROR: Invalid host_op '$HOST_OP'" >&2
  echo "WHY: This operation name doesn't match any registered handler in host-ops-executor.py." >&2
  echo "DO THIS: Use one of: $VALID_OPS" >&2
  echo "VERIFY: grep '\"$HOST_OP\"' /root/.openclaw/scripts/host-ops-executor.py" >&2
  exit 1
fi

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
m = {
    'host_op': sys.argv[1],
    'agent': sys.argv[2],
    # 12000 cap (was 1500): silent [:1500] amputated pushed-evidence prompts —
    # judges saw half the receipts (scar #22 + failsafe beat 2026-07-08).
    'prompt': sys.argv[3][:12000] + (' Context: ' + sys.argv[4] if sys.argv[4] else ''),
    'routing_mode': sys.argv[5],
    'telegram_chat_id': '8561305605',
}
if len(sys.argv) > 6 and sys.argv[6].strip().isdigit():
    m['timeout'] = int(sys.argv[6])
if len(sys.argv[3]) > 12000:
    # No silent caps, ever: the agent will NOT see the tail past 12000 chars.
    sys.stderr.write('WARN workshop-submit: prompt truncated %d->12000 chars — '
                     'shorten the prompt or split the task.\n' % len(sys.argv[3]))
print(json.dumps(m))
" "$HOST_OP" "$AGENT" "$TASK" "$CONTEXT" "$ROUTING_MODE" "$TIMEOUT_S")

# Insert task with meta
TASK_ID=$(python3 -c "
import sqlite3, sys, json
db = sqlite3.connect(sys.argv[1])
project_id = int(sys.argv[8]) if len(sys.argv) > 8 and sys.argv[8].strip().isdigit() else None
db.execute(
    'INSERT INTO tasks (agent, urgency, status, task, context, meta, blocked_by, project_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    (sys.argv[2], sys.argv[3], 'pending', sys.argv[4], sys.argv[5] or None, sys.argv[6], sys.argv[7] or None, project_id)
)
db.commit()
print(db.execute('SELECT last_insert_rowid()').fetchone()[0])
db.close()
" "$OPS_DB" "$AGENT" "$URGENCY" "$TASK" "$CONTEXT" "$META" "$BLOCKED_BY" "$PROJECT_ID")

echo "Task #${TASK_ID} created [${AGENT}/${URGENCY}/${HOST_OP}]: ${TASK}"
