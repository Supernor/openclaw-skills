#!/usr/bin/env bash
# check-feedback-answers.sh — Check for newly answered bearings questions
# Returns JSON of answers since last check. Updates last-check timestamp.
# Usage: check-feedback-answers.sh [source_prefix]
#   source_prefix: filter by trigger_source prefix (e.g. "reactor-" for reactor questions)

set -eo pipefail
OPS_DB="/root/.openclaw/ops.db"
PREFIX="${1:-reactor-}"
KV_KEY="feedback_last_check_${PREFIX}"

# Get last check time
LAST_CHECK=$(sqlite3 "$OPS_DB" "SELECT value FROM kv WHERE key='$KV_KEY'" 2>/dev/null || echo "2000-01-01T00:00:00Z")

# Get new answers
ANSWERS=$(sqlite3 -json "$OPS_DB" "
  SELECT id, trigger_source, substr(question_text,1,80) as question, response_value as answer, answered_at
  FROM bearings_queue
  WHERE trigger_source LIKE '${PREFIX}%'
    AND status='answered'
    AND answered_at > '$LAST_CHECK'
  ORDER BY answered_at
" 2>/dev/null)

# Update last check
sqlite3 "$OPS_DB" "INSERT OR REPLACE INTO kv (key, value, updated_at) VALUES ('$KV_KEY', datetime('now'), datetime('now'))" 2>/dev/null

# Output
if [ -n "$ANSWERS" ] && [ "$ANSWERS" != "[]" ]; then
  COUNT=$(echo "$ANSWERS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
  echo "$ANSWERS"
else
  echo "[]"
fi
