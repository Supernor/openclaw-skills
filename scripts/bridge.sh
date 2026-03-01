#!/usr/bin/env bash
# bridge.sh — Task flow manager for the OpenClaw bridge protocol
# Manages the full lifecycle: send → check → pickup → complete
# Keeps ops-db tasks table and bridge/inbox/outbox files in sync.
#
# Usage:
#   bridge.sh send <to-agent> <subject> [--priority X] [--desc "..."] [--files '["..."]']
#   bridge.sh check [agent-id]           # List pending tasks (from inbox/)
#   bridge.sh pickup <task-id>           # Agent claims a task
#   bridge.sh complete <task-id> <summary> [--changes '["..."]'] [--needs-restart]
#   bridge.sh fail <task-id> <reason>    # Mark task as failed
#   bridge.sh status                     # All tasks: pending, in-progress, completed
#   bridge.sh clean [--days N]           # Remove completed tasks older than N days (default 7)

set -eo pipefail

BASE="/home/node/.openclaw"
if [ ! -d "$BASE" ] && [ -d "/root/.openclaw" ]; then
  BASE="/root/.openclaw"
fi

BRIDGE="${BASE}/bridge"
INBOX="${BRIDGE}/inbox"
OUTBOX="${BRIDGE}/outbox"
OPSDB="${BASE}/scripts/ops-db.sh"

mkdir -p "$INBOX" "$OUTBOX"

CMD="${1:?Usage: bridge.sh <send|check|pickup|complete|fail|status|clean>}"

case "$CMD" in

  # ──── SEND (Claude Code → Agent) ────
  send)
    TO="${2:?Usage: bridge.sh send <to-agent> <subject>}"
    SUBJECT="${3:?Usage: bridge.sh send <to-agent> <subject>}"
    PRIORITY="normal" DESC="" FILES=""
    shift 3
    while [ $# -gt 0 ]; do
      case "$1" in
        --priority) PRIORITY="$2"; shift 2 ;;
        --desc) DESC="$2"; shift 2 ;;
        --files) FILES="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    SLUG=$(echo "$SUBJECT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 40)
    TASK_ID="${NOW//:/-}-${SLUG}"
    FILENAME="${TASK_ID}.json"

    # Create in ops-db
    URGENCY="routine"
    case "$PRIORITY" in
      urgent) URGENCY="critical" ;;
      high) URGENCY="high" ;;
      normal) URGENCY="routine" ;;
      low) URGENCY="low" ;;
    esac
    DB_RESULT=$("$OPSDB" task create "$TO" "$SUBJECT" --urgency "$URGENCY" --context "$DESC" --files "$FILES" 2>/dev/null || echo "[]")
    DB_ID=$(echo "$DB_RESULT" | jq -r '.[0].id // "unknown"' 2>/dev/null || echo "unknown")

    # Write inbox file
    jq -n \
      --arg id "$TASK_ID" \
      --arg dbId "$DB_ID" \
      --arg created "$NOW" \
      --arg to "$TO" \
      --arg priority "$PRIORITY" \
      --arg subject "$SUBJECT" \
      --arg desc "$DESC" \
      --arg files "$FILES" \
      '{
        id: $id,
        dbId: ($dbId | tonumber? // $dbId),
        created: $created,
        from: "claude-code",
        to: $to,
        priority: $priority,
        subject: $subject,
        description: $desc,
        files: (if $files != "" then ($files | fromjson? // []) else [] end),
        status: "pending"
      }' > "${INBOX}/${FILENAME}"

    echo "{\"status\":\"sent\",\"taskId\":\"$TASK_ID\",\"dbId\":$DB_ID,\"file\":\"inbox/$FILENAME\"}"
    ;;

  # ──── CHECK (Agent polls for tasks) ────
  check)
    AGENT="${2:-}"
    RESULTS="[]"
    for f in "$INBOX"/*.json; do
      [ -f "$f" ] || continue
      if [ -z "$AGENT" ]; then
        RESULTS=$(echo "$RESULTS" | jq --slurpfile task "$f" '. + $task')
      else
        TO=$(jq -r '.to' "$f" 2>/dev/null)
        if [ "$TO" = "$AGENT" ]; then
          RESULTS=$(echo "$RESULTS" | jq --slurpfile task "$f" '. + $task')
        fi
      fi
    done
    echo "$RESULTS" | jq -c '.'
    ;;

  # ──── PICKUP (Agent claims a task) ────
  pickup)
    TASK_ID="${2:?Usage: bridge.sh pickup <task-id>}"
    # Find the inbox file
    FOUND=""
    for f in "$INBOX"/*.json; do
      [ -f "$f" ] || continue
      FID=$(jq -r '.id' "$f" 2>/dev/null)
      if [ "$FID" = "$TASK_ID" ]; then
        FOUND="$f"
        break
      fi
    done
    if [ -z "$FOUND" ]; then
      echo "{\"error\":\"task not found in inbox\",\"taskId\":\"$TASK_ID\"}"
      exit 1
    fi

    # Update inbox file status
    jq '.status = "in-progress" | .pickedUpAt = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' "$FOUND" > "${FOUND}.tmp" && mv "${FOUND}.tmp" "$FOUND"

    # Update ops-db
    DB_ID=$(jq -r '.dbId' "$FOUND" 2>/dev/null)
    if [ "$DB_ID" != "null" ] && [ "$DB_ID" != "unknown" ]; then
      "$OPSDB" task update "$DB_ID" in-progress >/dev/null 2>&1 || true
    fi

    echo "{\"status\":\"picked-up\",\"taskId\":\"$TASK_ID\",\"dbId\":$DB_ID}"
    ;;

  # ──── COMPLETE (Agent finishes task) ────
  complete)
    TASK_ID="${2:?Usage: bridge.sh complete <task-id> <summary>}"
    SUMMARY="${3:?Usage: bridge.sh complete <task-id> <summary>}"
    CHANGES="" NEEDS_RESTART="false" FOLLOW_UP=""
    shift 3
    while [ $# -gt 0 ]; do
      case "$1" in
        --changes) CHANGES="$2"; shift 2 ;;
        --needs-restart) NEEDS_RESTART="true"; shift ;;
        --follow-up) FOLLOW_UP="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    # Find inbox file
    FOUND=""
    for f in "$INBOX"/*.json; do
      [ -f "$f" ] || continue
      FID=$(jq -r '.id' "$f" 2>/dev/null)
      if [ "$FID" = "$TASK_ID" ]; then
        FOUND="$f"
        break
      fi
    done
    if [ -z "$FOUND" ]; then
      echo "{\"error\":\"task not found in inbox\",\"taskId\":\"$TASK_ID\"}"
      exit 1
    fi

    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    FROM=$(jq -r '.to' "$FOUND" 2>/dev/null)
    DB_ID=$(jq -r '.dbId' "$FOUND" 2>/dev/null)

    # Write outbox result
    RESULT_FILE="${TASK_ID}-result.json"
    jq -n \
      --arg id "${TASK_ID}-result" \
      --arg taskId "$TASK_ID" \
      --arg dbId "$DB_ID" \
      --arg created "$NOW" \
      --arg from "$FROM" \
      --arg summary "$SUMMARY" \
      --arg changes "$CHANGES" \
      --arg needsRestart "$NEEDS_RESTART" \
      --arg followUp "$FOLLOW_UP" \
      '{
        id: $id,
        taskId: $taskId,
        dbId: ($dbId | tonumber? // $dbId),
        created: $created,
        from: $from,
        status: "completed",
        summary: $summary,
        changes: (if $changes != "" then ($changes | fromjson? // []) else [] end),
        needsRestart: ($needsRestart == "true"),
        followUp: (if $followUp != "" then $followUp else null end)
      }' > "${OUTBOX}/${RESULT_FILE}"

    # Update ops-db
    if [ "$DB_ID" != "null" ] && [ "$DB_ID" != "unknown" ]; then
      RESULT_JSON=$(jq -c '{summary, changes, needsRestart}' "${OUTBOX}/${RESULT_FILE}" 2>/dev/null || echo '{}')
      "$OPSDB" task update "$DB_ID" completed --result "$RESULT_JSON" >/dev/null 2>&1 || true
    fi

    # Move inbox file to outbox (archived alongside result)
    mv "$FOUND" "${OUTBOX}/${TASK_ID}-task.json"

    echo "{\"status\":\"completed\",\"taskId\":\"$TASK_ID\",\"resultFile\":\"outbox/$RESULT_FILE\"}"
    ;;

  # ──── FAIL (Agent can't complete task) ────
  fail)
    TASK_ID="${2:?Usage: bridge.sh fail <task-id> <reason>}"
    REASON="${3:?Usage: bridge.sh fail <task-id> <reason>}"

    FOUND=""
    for f in "$INBOX"/*.json; do
      [ -f "$f" ] || continue
      FID=$(jq -r '.id' "$f" 2>/dev/null)
      if [ "$FID" = "$TASK_ID" ]; then
        FOUND="$f"
        break
      fi
    done
    if [ -z "$FOUND" ]; then
      echo "{\"error\":\"task not found in inbox\",\"taskId\":\"$TASK_ID\"}"
      exit 1
    fi

    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    FROM=$(jq -r '.to' "$FOUND" 2>/dev/null)
    DB_ID=$(jq -r '.dbId' "$FOUND" 2>/dev/null)

    RESULT_FILE="${TASK_ID}-result.json"
    jq -n \
      --arg id "${TASK_ID}-result" \
      --arg taskId "$TASK_ID" \
      --arg dbId "$DB_ID" \
      --arg created "$NOW" \
      --arg from "$FROM" \
      --arg reason "$REASON" \
      '{
        id: $id,
        taskId: $taskId,
        dbId: ($dbId | tonumber? // $dbId),
        created: $created,
        from: $from,
        status: "failed",
        reason: $reason
      }' > "${OUTBOX}/${RESULT_FILE}"

    if [ "$DB_ID" != "null" ] && [ "$DB_ID" != "unknown" ]; then
      "$OPSDB" task update "$DB_ID" failed --result "{\"reason\":\"$REASON\"}" >/dev/null 2>&1 || true
    fi

    mv "$FOUND" "${OUTBOX}/${TASK_ID}-task.json"
    echo "{\"status\":\"failed\",\"taskId\":\"$TASK_ID\",\"reason\":\"$REASON\"}"
    ;;

  # ──── STATUS (overview) ────
  status)
    INBOX_COUNT=0 INPROGRESS_COUNT=0
    INBOX_TASKS="[]"
    for f in "$INBOX"/*.json; do
      [ -f "$f" ] || continue
      STATUS=$(jq -r '.status' "$f" 2>/dev/null)
      INBOX_TASKS=$(echo "$INBOX_TASKS" | jq --slurpfile t "$f" '. + [$t[0] | {id, to, subject, priority, status, created}]')
      if [ "$STATUS" = "pending" ]; then INBOX_COUNT=$((INBOX_COUNT + 1)); fi
      if [ "$STATUS" = "in-progress" ]; then INPROGRESS_COUNT=$((INPROGRESS_COUNT + 1)); fi
    done

    OUTBOX_COUNT=0
    OUTBOX_RESULTS="[]"
    for f in "$OUTBOX"/*-result.json; do
      [ -f "$f" ] || continue
      OUTBOX_COUNT=$((OUTBOX_COUNT + 1))
      OUTBOX_RESULTS=$(echo "$OUTBOX_RESULTS" | jq --slurpfile t "$f" '. + [$t[0] | {id, taskId, from, status, summary, created}]')
    done

    jq -n \
      --argjson pending "$INBOX_COUNT" \
      --argjson inProgress "$INPROGRESS_COUNT" \
      --argjson completed "$OUTBOX_COUNT" \
      --argjson inbox "$INBOX_TASKS" \
      --argjson outbox "$OUTBOX_RESULTS" \
      '{
        summary: {pending: $pending, inProgress: $inProgress, completed: $completed},
        inbox: $inbox,
        outbox: $outbox
      }'
    ;;

  # ──── CLEAN (prune old completed tasks) ────
  clean)
    DAYS=7
    [ "${2:-}" = "--days" ] && DAYS="${3:-7}"
    CUTOFF=$(date -u -d "$DAYS days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
    CLEANED=0
    for f in "$OUTBOX"/*.json; do
      [ -f "$f" ] || continue
      CREATED=$(jq -r '.created // ""' "$f" 2>/dev/null)
      if [ -n "$CREATED" ] && [ "$CREATED" \< "$CUTOFF" ]; then
        rm "$f"
        CLEANED=$((CLEANED + 1))
      fi
    done
    echo "{\"status\":\"ok\",\"cleaned\":$CLEANED,\"olderThan\":\"$CUTOFF\"}"
    ;;

  *)
    echo '{"error":"Unknown command: '"$CMD"'","usage":"bridge.sh <send|check|pickup|complete|fail|status|clean>"}' >&2
    exit 1
    ;;
esac
