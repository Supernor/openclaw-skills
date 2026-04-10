#!/usr/bin/env bash
# Alignment: compact task_steps rows older than N days into summary rows.
# Role: keep ops.db lean by compressing old step data into one summary per task.
# Dependencies: ops.db (task_steps table), sqlite3.
# Key patterns: for each task with old steps, keep first + last step, create one summary
# row with aggregated tokens/duration, delete the originals. Safe no-op when no data qualifies.
# Usage: compact-task-steps.sh [days]  (default: 30)
# Reference: chart infra-activity-streaming-layer (30-day retention design decision)

set -eo pipefail

DAYS="${1:-30}"
OPS_DB="/root/.openclaw/ops.db"

# Count rows that qualify for compaction
STALE_COUNT=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM task_steps WHERE created_at < datetime('now', '-${DAYS} days')")

if [ "$STALE_COUNT" -eq 0 ]; then
    echo "No task_steps older than ${DAYS} days. Nothing to compact."
    exit 0
fi

echo "Found ${STALE_COUNT} task_steps older than ${DAYS} days. Compacting..."

# Get distinct task_ids with stale steps
TASK_IDS=$(sqlite3 "$OPS_DB" "SELECT DISTINCT task_id FROM task_steps WHERE created_at < datetime('now', '-${DAYS} days')")

COMPACTED=0
for TID in $TASK_IDS; do
    # Get step count for this task
    STEP_COUNT=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM task_steps WHERE task_id=${TID}")
    if [ "$STEP_COUNT" -le 2 ]; then
        continue  # Keep tasks with 1-2 steps as-is
    fi

    # Aggregate: total tokens, total duration, step count
    AGG=$(sqlite3 -separator '|' "$OPS_DB" "
        SELECT COALESCE(SUM(tokens_used),0), COALESCE(SUM(duration_ms),0), COUNT(*)
        FROM task_steps WHERE task_id=${TID} AND created_at < datetime('now', '-${DAYS} days')
    ")
    TOTAL_TOKENS=$(echo "$AGG" | cut -d'|' -f1)
    TOTAL_DURATION=$(echo "$AGG" | cut -d'|' -f2)
    TOTAL_STEPS=$(echo "$AGG" | cut -d'|' -f3)

    if [ "$TOTAL_STEPS" -eq 0 ]; then
        continue
    fi

    # Get first and last step summaries for context
    FIRST=$(sqlite3 "$OPS_DB" "SELECT summary FROM task_steps WHERE task_id=${TID} ORDER BY step_index ASC LIMIT 1" | tr "'" "_" | head -c 200)
    LAST=$(sqlite3 "$OPS_DB" "SELECT summary FROM task_steps WHERE task_id=${TID} ORDER BY step_index DESC LIMIT 1" | tr "'" "_" | head -c 200)

    # Delete old steps (keep any that are within retention window)
    sqlite3 "$OPS_DB" "DELETE FROM task_steps WHERE task_id=${TID} AND created_at < datetime('now', '-${DAYS} days')"

    # Insert compact summary row
    sqlite3 "$OPS_DB" "
        INSERT INTO task_steps (task_id, step_index, step_type, tool_name, summary, detail, tokens_used, duration_ms, status)
        VALUES (${TID}, 0, 'compact', 'archival', 'Compacted ${TOTAL_STEPS} steps (${DAYS}d+ old)', 'First: ${FIRST} | Last: ${LAST}', ${TOTAL_TOKENS}, ${TOTAL_DURATION}, 'completed')
    "

    COMPACTED=$((COMPACTED + 1))
done

echo "Compacted ${COMPACTED} tasks (${STALE_COUNT} steps archived)."

# Also compact cron_outcomes if they exist and are old
CRON_STALE=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM cron_outcomes WHERE ran_at < datetime('now', '-${DAYS} days')" 2>/dev/null || echo 0)
if [ "$CRON_STALE" -gt 0 ]; then
    sqlite3 "$OPS_DB" "DELETE FROM cron_outcomes WHERE ran_at < datetime('now', '-${DAYS} days')"
    echo "Cleaned ${CRON_STALE} old cron_outcomes."
fi

echo "Done."
