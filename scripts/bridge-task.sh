#!/usr/bin/env bash
# bridge-task.sh — Queue a Bridge edit task for the task-runner
# Usage: bridge-task.sh "make the agent tiles bigger"

PROMPT="$1"
if [ -z "$PROMPT" ]; then
  echo "Usage: bridge-task.sh 'description of change'"
  exit 1
fi

CONTEXT=$(cat /root/.openclaw/scripts/dashboard-edit-context.md)

sqlite3 /root/.openclaw/ops.db "INSERT INTO tasks (agent, urgency, status, task, context) VALUES (
  'spec-dev', 'routine', 'pending',
  'Bridge edit: $(echo "$PROMPT" | sed "s/'/''/g")',
  '$(echo "$CONTEXT" | sed "s/'/''/g")

---

User request: $(echo "$PROMPT" | sed "s/'/''/g")'
);"

TASK_ID=$(sqlite3 /root/.openclaw/ops.db "SELECT MAX(id) FROM tasks")
echo "Queued Bridge edit as task #${TASK_ID}. Task-runner picks up every 15 min."
