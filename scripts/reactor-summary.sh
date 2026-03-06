#!/usr/bin/env bash
# reactor-summary.sh — Generate card-ready summary payload for Relay auto-notify
# Works from host OR container. Reads from all data stores (SQL, JSONL, outbox).
#
# Usage:
#   reactor-summary.sh last                    # Latest completed/failed task
#   reactor-summary.sh task <task-id>          # Specific task
#   reactor-summary.sh channel <channel-id>    # Latest task for a channel
#   reactor-summary.sh pending                 # All pending handoffs not yet consumed
#
# Output: JSON payload ready for Discord card rendering (embed-compatible).
# Relay can call this and forward the JSON directly to Discord formatting.

set -eo pipefail

BASE="/root/.openclaw"
if [ ! -d "$BASE" ] && [ -d "/home/node/.openclaw" ]; then
  BASE="/home/node/.openclaw"
fi

LEDGER_DB="${BASE}/bridge/reactor-ledger.sqlite"
OUTBOX="${BASE}/bridge/outbox"
EVENTS_FILE="${BASE}/bridge/events/reactor.jsonl"

sql() {
  sqlite3 -json "$LEDGER_DB" "$@" 2>/dev/null
}

sql_val() {
  sqlite3 "$LEDGER_DB" "$@" 2>/dev/null || echo ""
}

# Build a card-ready JSON payload from a task_id
build_card() {
  local task_id="$1"

  # Job row
  local subject status duration_s tool_count result_preview date_finished channel_id rhr rhs
  subject=$(sql_val "SELECT subject FROM jobs WHERE task_id='$task_id';")
  status=$(sql_val "SELECT status FROM jobs WHERE task_id='$task_id';")
  duration_s=$(sql_val "SELECT COALESCE(duration_seconds,0) FROM jobs WHERE task_id='$task_id';")
  tool_count=$(sql_val "SELECT COALESCE(tool_count,0) FROM jobs WHERE task_id='$task_id';")
  result_preview=$(sql_val "SELECT COALESCE(result_preview,'') FROM jobs WHERE task_id='$task_id';")
  date_finished=$(sql_val "SELECT COALESCE(date_finished,'') FROM jobs WHERE task_id='$task_id';")
  channel_id=$(sql_val "SELECT COALESCE(channel_id,'') FROM jobs WHERE task_id='$task_id';")
  rhr=$(sql_val "SELECT relay_handoff_required FROM jobs WHERE task_id='$task_id';")
  rhs=$(sql_val "SELECT relay_handoff_sent FROM jobs WHERE task_id='$task_id';")

  if [ -z "$subject" ]; then
    echo '{"error":"task not found","taskId":"'"$task_id"'"}'
    return 1
  fi

  # Format duration
  local duration_str=""
  if [ "$duration_s" -gt 0 ] 2>/dev/null; then
    if [ "$duration_s" -lt 60 ]; then
      duration_str="${duration_s}s"
    elif [ "$duration_s" -lt 3600 ]; then
      duration_str="$((duration_s / 60))m $((duration_s % 60))s"
    else
      duration_str="$((duration_s / 3600))h $((duration_s % 3600 / 60))m"
    fi
  fi

  # Status emoji for Discord
  local status_emoji=""
  case "$status" in
    completed) status_emoji="OK" ;;
    failed|timeout) status_emoji="FAIL" ;;
    in-progress) status_emoji="RUNNING" ;;
    pending) status_emoji="PENDING" ;;
    *) status_emoji="?" ;;
  esac

  # Full result from outbox (if available)
  local full_summary=""
  local handoff_file="${OUTBOX}/${task_id}-handoff.json"
  local result_file="${OUTBOX}/${task_id}-result.json"

  if [ -f "$result_file" ]; then
    full_summary=$(jq -r '.summary // .reason // ""' "$result_file" 2>/dev/null | head -c 4000)
  fi
  if [ -z "$full_summary" ]; then
    full_summary="$result_preview"
  fi

  # Retro data
  local wins losses learnings
  wins=$(sql_val "SELECT COALESCE(wins,'') FROM retros WHERE task_id='$task_id' ORDER BY created_at DESC LIMIT 1;")
  losses=$(sql_val "SELECT COALESCE(losses,'') FROM retros WHERE task_id='$task_id' ORDER BY created_at DESC LIMIT 1;")
  learnings=$(sql_val "SELECT COALESCE(learnings,'') FROM retros WHERE task_id='$task_id' ORDER BY created_at DESC LIMIT 1;")

  # Open questions
  local questions_json
  questions_json=$(sql "SELECT question_text FROM questions WHERE task_id='$task_id' AND answered=0;" 2>/dev/null || echo "[]")
  [ -z "$questions_json" ] && questions_json="[]"

  # Known issues block (auto-suppressed when no open items)
  local known_issues_json="null"
  local ki_snapshot="${BASE}/bridge/known-issues.json"
  if [ -f "$ki_snapshot" ]; then
    local ki_count
    ki_count=$(jq -r '.openCount // 0' "$ki_snapshot" 2>/dev/null)
    if [ "$ki_count" -gt 0 ] 2>/dev/null; then
      known_issues_json=$(jq '{
        chartId: .chartId,
        openCount: .openCount,
        items: [ .items[] | "\(.status): \(.title)" ] | join(" | "),
        snapshotAge: .updated
      }' "$ki_snapshot" 2>/dev/null || echo "null")
    fi
  fi

  # Build the card payload
  jq -n \
    --arg task_id "$task_id" \
    --arg subject "$subject" \
    --arg status "$status" \
    --arg status_emoji "$status_emoji" \
    --arg duration "$duration_str" \
    --argjson tool_count "$tool_count" \
    --arg date_finished "$date_finished" \
    --arg channel_id "$channel_id" \
    --arg summary "$full_summary" \
    --arg wins "$wins" \
    --arg losses "$losses" \
    --arg learnings "$learnings" \
    --argjson questions "$questions_json" \
    --argjson handoff_required "${rhr:-0}" \
    --argjson handoff_sent "${rhs:-0}" \
    --argjson known_issues "$known_issues_json" \
    '{
      type: "reactor-summary-card",
      taskId: $task_id,
      subject: $subject,
      status: $status,
      statusEmoji: $status_emoji,
      duration: (if $duration != "" then $duration else null end),
      toolCount: $tool_count,
      completedAt: (if $date_finished != "" then $date_finished else null end),
      channelId: (if $channel_id != "" then $channel_id else null end),
      summary: (if $summary != "" then $summary else null end),
      retro: {
        wins: (if $wins != "" then $wins else null end),
        losses: (if $losses != "" then $losses else null end),
        learnings: (if $learnings != "" then $learnings else null end)
      },
      questions: $questions,
      handoff: {
        required: ($handoff_required == 1),
        sent: ($handoff_sent == 1)
      }
    } + (if $known_issues != null then { knownIssues: $known_issues } else {} end)'
}

CMD="${1:-help}"

case "$CMD" in

  last)
    # Find the most recently finished task
    TASK_ID=$(sql_val "SELECT task_id FROM jobs WHERE status IN ('completed','failed','timeout') ORDER BY date_finished DESC LIMIT 1;")
    if [ -z "$TASK_ID" ]; then
      echo '{"error":"no completed tasks found"}'
      exit 1
    fi
    build_card "$TASK_ID"
    ;;

  task)
    TASK_ID="${2:?Usage: reactor-summary.sh task <task-id>}"
    build_card "$TASK_ID"
    ;;

  channel)
    CHAN_ID="${2:?Usage: reactor-summary.sh channel <channel-id>}"
    TASK_ID=$(sql_val "SELECT task_id FROM jobs WHERE channel_id='$CHAN_ID' ORDER BY date_received DESC LIMIT 1;")
    if [ -z "$TASK_ID" ]; then
      echo '{"error":"no tasks found for channel","channelId":"'"$CHAN_ID"'"}'
      exit 1
    fi
    build_card "$TASK_ID"
    ;;

  pending)
    # All tasks with handoff_required=1 but handoff_sent=0
    TASKS=$(sql_val "SELECT task_id FROM jobs WHERE relay_handoff_required=1 AND relay_handoff_sent=0;")
    if [ -z "$TASKS" ]; then
      echo '{"pending":[]}'
      exit 0
    fi
    echo '{"pending":['
    FIRST=true
    while IFS= read -r tid; do
      [ -z "$tid" ] && continue
      if $FIRST; then FIRST=false; else echo ","; fi
      build_card "$tid"
    done <<< "$TASKS"
    echo ']}'
    ;;

  help|*)
    cat <<'EOF'
reactor-summary.sh — Card-ready summary payload for Relay auto-notify

Commands:
  last                    Latest completed/failed task summary
  task <task-id>          Summary for a specific task
  channel <channel-id>    Latest task for a Discord channel
  pending                 All pending handoffs (not yet consumed by Relay)

Output: JSON payload with type "reactor-summary-card".
Fields: taskId, subject, status, statusEmoji, duration, toolCount,
        completedAt, channelId, summary, retro{wins,losses,learnings},
        questions[], handoff{required,sent}
EOF
    ;;
esac
