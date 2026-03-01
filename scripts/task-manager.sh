#!/usr/bin/env bash
# task-manager.sh — Task CRUD for project channels
# Usage:
#   task-manager.sh add <channel> <title> [--assign <agent>] [--link <decision#>]
#   task-manager.sh done <channel> <id>
#   task-manager.sh update <channel> <id> <status> [--assign <agent>]
#   task-manager.sh list <channel> [--status <todo|in-progress|done|all>]
#   task-manager.sh get <channel> <id>
#   task-manager.sh remove <channel> <id>
#   task-manager.sh summary <channel>   # counts by status

set -eo pipefail

BASE="/home/node/.openclaw"
TASKS_DIR="$BASE/workspace-spec-projects/tasks"
mkdir -p "$TASKS_DIR"

ACTION="${1:-}"
CHANNEL="${2:-}"

if [ -z "$ACTION" ] || [ -z "$CHANNEL" ] && [ "$ACTION" != "help" ]; then
  echo '{"error":"Usage: task-manager.sh <add|done|update|list|get|remove|summary> <channel> [args]"}' | jq .
  exit 1
fi

TASK_FILE="$TASKS_DIR/${CHANNEL}.json"

# Initialize file if missing
init_file() {
  [ -f "$TASK_FILE" ] || echo '{"channel":"'"$CHANNEL"'","nextId":1,"tasks":[]}' > "$TASK_FILE"
}

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

case "$ACTION" in
  add)
    init_file
    shift 2  # past action and channel
    TITLE=""
    ASSIGNEE=""
    LINK=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --assign) ASSIGNEE="$2"; shift 2 ;;
        --link) LINK="$2"; shift 2 ;;
        *) TITLE="$TITLE $1"; shift ;;
      esac
    done
    TITLE=$(echo "$TITLE" | sed 's/^ //')

    if [ -z "$TITLE" ]; then
      echo '{"error":"Title required: task-manager.sh add <channel> <title>"}' | jq .
      exit 1
    fi

    TMP=$(mktemp)
    NEXT_ID=$(jq '.nextId' "$TASK_FILE")
    jq --arg t "$TITLE" --arg a "$ASSIGNEE" --arg l "$LINK" --arg now "$NOW" --argjson id "$NEXT_ID" '
      .nextId = ($id + 1) |
      .tasks += [{
        id: $id,
        title: $t,
        status: "todo",
        assignee: (if $a == "" then null else $a end),
        linkedDecision: (if $l == "" then null else ($l | tonumber) end),
        created: $now,
        updated: $now
      }]
    ' "$TASK_FILE" > "$TMP" && mv "$TMP" "$TASK_FILE"

    jq --argjson id "$NEXT_ID" '.tasks[] | select(.id == $id)' "$TASK_FILE" | jq '. + {action: "created"}'
    ;;

  done)
    init_file
    TASK_ID="${3:-}"
    [ -z "$TASK_ID" ] && { echo '{"error":"Usage: task-manager.sh done <channel> <id>"}' | jq .; exit 1; }

    # Verify task exists
    EXISTS=$(jq --argjson id "$TASK_ID" '[.tasks[] | select(.id == ($id | tonumber))] | length' "$TASK_FILE")
    [ "$EXISTS" -eq 0 ] && { echo "{\"error\":\"Task $TASK_ID not found in $CHANNEL\"}" | jq .; exit 1; }

    TMP=$(mktemp)
    jq --argjson id "$TASK_ID" --arg now "$NOW" '
      .tasks = [.tasks[] | if .id == ($id | tonumber) then .status = "done" | .updated = $now else . end]
    ' "$TASK_FILE" > "$TMP" && mv "$TMP" "$TASK_FILE"

    jq --argjson id "$TASK_ID" '.tasks[] | select(.id == ($id | tonumber))' "$TASK_FILE" | jq '. + {action: "completed"}'
    ;;

  update)
    init_file
    TASK_ID="${3:-}"
    NEW_STATUS="${4:-}"
    [ -z "$TASK_ID" ] || [ -z "$NEW_STATUS" ] && { echo '{"error":"Usage: task-manager.sh update <channel> <id> <status> [--assign <agent>]"}' | jq .; exit 1; }

    VALID_STATUSES="todo in-progress done blocked"
    if ! echo "$VALID_STATUSES" | grep -qw "$NEW_STATUS"; then
      echo "{\"error\":\"Invalid status: $NEW_STATUS\",\"valid\":[\"todo\",\"in-progress\",\"done\",\"blocked\"]}" | jq .
      exit 1
    fi

    EXISTS=$(jq --argjson id "$TASK_ID" '[.tasks[] | select(.id == ($id | tonumber))] | length' "$TASK_FILE")
    [ "$EXISTS" -eq 0 ] && { echo "{\"error\":\"Task $TASK_ID not found in $CHANNEL\"}" | jq .; exit 1; }

    # Check for --assign
    ASSIGNEE=""
    shift 4
    while [ $# -gt 0 ]; do
      case "$1" in
        --assign) ASSIGNEE="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    TMP=$(mktemp)
    if [ -n "$ASSIGNEE" ]; then
      jq --argjson id "$TASK_ID" --arg s "$NEW_STATUS" --arg a "$ASSIGNEE" --arg now "$NOW" '
        .tasks = [.tasks[] | if .id == ($id | tonumber) then .status = $s | .assignee = $a | .updated = $now else . end]
      ' "$TASK_FILE" > "$TMP" && mv "$TMP" "$TASK_FILE"
    else
      jq --argjson id "$TASK_ID" --arg s "$NEW_STATUS" --arg now "$NOW" '
        .tasks = [.tasks[] | if .id == ($id | tonumber) then .status = $s | .updated = $now else . end]
      ' "$TASK_FILE" > "$TMP" && mv "$TMP" "$TASK_FILE"
    fi

    jq --argjson id "$TASK_ID" '.tasks[] | select(.id == ($id | tonumber))' "$TASK_FILE" | jq '. + {action: "updated"}'
    ;;

  list)
    init_file
    STATUS_FILTER="${3:-all}"
    if [ "$STATUS_FILTER" = "all" ] || [ "$STATUS_FILTER" = "--status" ]; then
      [ "$STATUS_FILTER" = "--status" ] && STATUS_FILTER="${4:-all}"
    fi

    if [ "$STATUS_FILTER" = "all" ]; then
      jq '{channel: .channel, total: (.tasks | length), tasks: .tasks}' "$TASK_FILE"
    else
      jq --arg s "$STATUS_FILTER" '{
        channel: .channel,
        filter: $s,
        count: ([.tasks[] | select(.status == $s)] | length),
        tasks: [.tasks[] | select(.status == $s)]
      }' "$TASK_FILE"
    fi
    ;;

  get)
    init_file
    TASK_ID="${3:-}"
    [ -z "$TASK_ID" ] && { echo '{"error":"Usage: task-manager.sh get <channel> <id>"}' | jq .; exit 1; }

    TASK=$(jq --argjson id "$TASK_ID" '.tasks[] | select(.id == ($id | tonumber))' "$TASK_FILE")
    if [ -z "$TASK" ]; then
      echo "{\"error\":\"Task $TASK_ID not found in $CHANNEL\"}" | jq .
      exit 1
    fi
    echo "$TASK"
    ;;

  remove)
    init_file
    TASK_ID="${3:-}"
    [ -z "$TASK_ID" ] && { echo '{"error":"Usage: task-manager.sh remove <channel> <id>"}' | jq .; exit 1; }

    EXISTS=$(jq --argjson id "$TASK_ID" '[.tasks[] | select(.id == ($id | tonumber))] | length' "$TASK_FILE")
    [ "$EXISTS" -eq 0 ] && { echo "{\"error\":\"Task $TASK_ID not found in $CHANNEL\"}" | jq .; exit 1; }

    REMOVED=$(jq --argjson id "$TASK_ID" '.tasks[] | select(.id == ($id | tonumber))' "$TASK_FILE")
    TMP=$(mktemp)
    jq --argjson id "$TASK_ID" '
      .tasks = [.tasks[] | select(.id != ($id | tonumber))]
    ' "$TASK_FILE" > "$TMP" && mv "$TMP" "$TASK_FILE"

    echo "$REMOVED" | jq '. + {action: "removed"}'
    ;;

  summary)
    init_file
    jq '{
      channel: .channel,
      total: (.tasks | length),
      todo: ([.tasks[] | select(.status == "todo")] | length),
      inProgress: ([.tasks[] | select(.status == "in-progress")] | length),
      blocked: ([.tasks[] | select(.status == "blocked")] | length),
      done: ([.tasks[] | select(.status == "done")] | length),
      assignees: ([.tasks[] | select(.assignee != null) | .assignee] | unique),
      linkedDecisions: ([.tasks[] | select(.linkedDecision != null) | .linkedDecision] | unique),
      lastUpdated: ([.tasks[].updated] | sort | last // null)
    }' "$TASK_FILE"
    ;;

  *)
    echo '{"error":"Unknown action","usage":"task-manager.sh <add|done|update|list|get|remove|summary> <channel> [args]"}' | jq .
    exit 1
    ;;
esac
