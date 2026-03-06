#!/usr/bin/env bash
# project-card.sh — Combined Last Run Summary + Project Health card
# Entrypoint for Relay to fetch a card-ready JSON payload.
#
# Usage:
#   project-card.sh <channel-id>            # Card for a specific channel (positional)
#   project-card.sh --channel-id <id>       # Card for a specific channel (explicit flag)
#   project-card.sh --current               # Latest completed task (any channel)
#   project-card.sh --channel-name <name>   # Resolve by channel name, not ID
#
# Output: JSON with type "project-card"
# Combines: reactor-summary (last task) + project health (decisions/tasks) + known issues

set -eo pipefail

BASE="/root/.openclaw"
if [ ! -d "$BASE" ] && [ -d "/home/node/.openclaw" ]; then
  BASE="/home/node/.openclaw"
fi

SCRIPTS="${BASE}/scripts"
PROJECTS_DIR="${BASE}/workspace-spec-projects"
DECISIONS_DIR="${PROJECTS_DIR}/decisions"
TASKS_DIR="${PROJECTS_DIR}/tasks"
LEDGER_DB="${BASE}/bridge/reactor-ledger.sqlite"
CHANNEL_MAP="${BASE}/bridge/channel-map.json"

# ── Channel resolution helpers ──
# Resolve channel ID → name using channel-map.json
resolve_name_from_id() {
  local id="$1"
  if [ -f "$CHANNEL_MAP" ] && command -v jq &>/dev/null; then
    local name
    name=$(jq -r --arg id "$id" '.byId[$id] // empty' "$CHANNEL_MAP" 2>/dev/null)
    if [ -n "$name" ]; then
      echo "$name"
      return
    fi
    # Check DM users
    name=$(jq -r --arg id "$id" '.dmUsers[$id] // empty' "$CHANNEL_MAP" 2>/dev/null)
    if [ -n "$name" ]; then
      echo "dm-${name}"
      return
    fi
  fi
}

# Resolve channel name → ID using channel-map.json
resolve_id_from_name() {
  local name="$1"
  if [ -f "$CHANNEL_MAP" ] && command -v jq &>/dev/null; then
    jq -r --arg name "$name" '.byName[$name] // empty' "$CHANNEL_MAP" 2>/dev/null
  fi
}

# ── Parse args ──
CHANNEL_ID=""
CHANNEL_NAME=""
MODE="channel"  # channel | current | name

case "${1:-help}" in
  --current)
    MODE="current"
    ;;
  --channel-name)
    MODE="name"
    CHANNEL_NAME="${2:?Usage: project-card.sh --channel-name <name>}"
    ;;
  --channel-id)
    MODE="channel"
    CHANNEL_ID="${2:?Usage: project-card.sh --channel-id <id>}"
    # Validate channel ID: must be 17-20 digits (Discord snowflake)
    if ! echo "$CHANNEL_ID" | grep -qE '^[0-9]{17,20}$'; then
      jq -n --arg input "$CHANNEL_ID" '{
        type: "project-card",
        error: "invalid-channel-id",
        message: ("Invalid channel ID: " + $input + ". Expected 17-20 digit Discord snowflake."),
        channelId: null,
        channelName: null,
        reactor: null,
        project: null
      }'
      exit 1
    fi
    ;;
  help|--help|-h)
    cat <<'EOF'
project-card.sh — Combined Last Run Summary + Project Health card

Usage:
  project-card.sh <channel-id>            Card for a specific Discord channel (positional)
  project-card.sh --channel-id <id>       Card for a specific Discord channel (explicit flag)
  project-card.sh --current               Latest completed task (any channel)
  project-card.sh --channel-name <name>   Resolve by channel name

Output: JSON payload with type "project-card"
Fields: channelId, channelName, reactor{...}, project{...}, knownIssues{...}
EOF
    exit 0
    ;;
  *)
    CHANNEL_ID="$1"
    # Validate channel ID: must be 17-20 digits (Discord snowflake)
    if ! echo "$CHANNEL_ID" | grep -qE '^[0-9]{17,20}$'; then
      jq -n --arg input "$CHANNEL_ID" '{
        type: "project-card",
        error: "invalid-channel-id",
        message: ("Invalid channel ID: " + $input + ". Expected 17-20 digit Discord snowflake."),
        channelId: null,
        channelName: null,
        reactor: null,
        project: null
      }'
      exit 1
    fi
    ;;
esac

# ── Resolve channel context for --current and --channel-name modes ──
case "$MODE" in
  name)
    # Resolve name → ID via channel map
    CHANNEL_ID=$(resolve_id_from_name "$CHANNEL_NAME")
    if [ -z "$CHANNEL_ID" ]; then
      # Fallback: search ledger subjects
      if [ -f "$LEDGER_DB" ] && command -v sqlite3 &>/dev/null; then
        CHANNEL_ID=$(sqlite3 "$LEDGER_DB" "SELECT channel_id FROM jobs WHERE subject LIKE '%${CHANNEL_NAME}%' AND channel_id != '' ORDER BY date_received DESC LIMIT 1;" 2>/dev/null)
      fi
    fi
    # If we got a channel_id but no name was in the map, keep the user-supplied name
    ;;
  channel)
    # Resolve ID → name via channel map
    CHANNEL_NAME=$(resolve_name_from_id "$CHANNEL_ID")
    ;;
esac

# ── 1. Reactor summary ──
REACTOR_JSON='null'

if [ -x "${SCRIPTS}/reactor-summary.sh" ]; then
  case "$MODE" in
    channel|name)
      if [ -n "$CHANNEL_ID" ]; then
        REACTOR_JSON=$("${SCRIPTS}/reactor-summary.sh" channel "$CHANNEL_ID" 2>/dev/null) || REACTOR_JSON='null'
      else
        # No channel_id resolved — try last task as fallback
        REACTOR_JSON=$("${SCRIPTS}/reactor-summary.sh" last 2>/dev/null) || REACTOR_JSON='null'
      fi
      ;;
    current)
      REACTOR_JSON=$("${SCRIPTS}/reactor-summary.sh" last 2>/dev/null) || REACTOR_JSON='null'
      # Extract channel_id from the result for project lookup
      CHANNEL_ID=$(echo "$REACTOR_JSON" | jq -r '.channelId // empty' 2>/dev/null)
      # Resolve the channel name from the extracted ID
      if [ -n "$CHANNEL_ID" ]; then
        CHANNEL_NAME=$(resolve_name_from_id "$CHANNEL_ID")
      fi
      ;;
  esac
fi

# Validate reactor JSON
echo "$REACTOR_JSON" | jq empty 2>/dev/null || REACTOR_JSON='null'
# Check for error responses
if echo "$REACTOR_JSON" | jq -e '.error' &>/dev/null; then
  REACTOR_JSON='null'
fi

# ── 2. Project health ──
PROJECT_JSON='null'

# Try to find project name from channel name or channel ID mapping
# Convention: project files use channel names, not IDs
resolve_project_name() {
  # If we have a channel name, use it directly
  if [ -n "$CHANNEL_NAME" ]; then
    # Strip dm- prefix for project file lookup
    local lookup_name="${CHANNEL_NAME#dm-}"
    if [ -f "${DECISIONS_DIR}/${lookup_name}.md" ] || [ -f "${TASKS_DIR}/${lookup_name}.json" ]; then
      echo "$lookup_name"
      return
    fi
  fi

  # If we have a channel_id, try to find project by scanning ledger subjects
  if [ -n "$CHANNEL_ID" ] && [ -f "$LEDGER_DB" ] && command -v sqlite3 &>/dev/null; then
    # Get recent subjects for this channel
    local subjects
    subjects=$(sqlite3 "$LEDGER_DB" "SELECT DISTINCT subject FROM jobs WHERE channel_id='${CHANNEL_ID}' ORDER BY date_received DESC LIMIT 5;" 2>/dev/null)
    while IFS= read -r subject; do
      [ -z "$subject" ] && continue
      # Try progressively shorter hyphenated prefixes: "memory-cop-deep-pass" -> "memory-cop-deep" -> "memory-cop"
      local parts
      IFS='-' read -ra parts <<< "$subject"
      local i=${#parts[@]}
      while [ "$i" -gt 1 ]; do
        local candidate
        candidate=$(IFS='-'; echo "${parts[*]:0:$i}")
        if [ -f "${DECISIONS_DIR}/${candidate}.md" ] || [ -f "${TASKS_DIR}/${candidate}.json" ]; then
          echo "$candidate"
          return
        fi
        i=$((i - 1))
      done
    done <<< "$subjects"
  fi

  # Last resort: if we have a channel name, try it as a project name even without matching files
  if [ -n "$CHANNEL_NAME" ]; then
    local lookup_name="${CHANNEL_NAME#dm-}"
    echo "$lookup_name"
    return
  fi
}

PROJECT_NAME=$(resolve_project_name)

if [ -n "$PROJECT_NAME" ]; then
  # Decisions count
  DECISIONS_FILE="${DECISIONS_DIR}/${PROJECT_NAME}.md"
  TASKS_FILE="${TASKS_DIR}/${PROJECT_NAME}.json"

  D_TOTAL=0
  D_DONE=0
  D_UNDECIDED=0
  D_OTHER=0

  if [ -f "$DECISIONS_FILE" ]; then
    D_DONE=$(grep -c '\[DONE\]' "$DECISIONS_FILE" 2>/dev/null || true)
    D_DONE=${D_DONE:-0}; D_DONE=${D_DONE// /}
    D_UNDECIDED=$(grep -c '\[UNDECIDED\]' "$DECISIONS_FILE" 2>/dev/null || true)
    D_UNDECIDED=${D_UNDECIDED:-0}; D_UNDECIDED=${D_UNDECIDED// /}
    D_OTHER=$(grep -cE '\[(DECIDED-NOT-DONE|SAVE-FOR-LATER|WONT-WORK)\]' "$DECISIONS_FILE" 2>/dev/null || true)
    D_OTHER=${D_OTHER:-0}; D_OTHER=${D_OTHER// /}
    D_TOTAL=$((${D_DONE:-0} + ${D_UNDECIDED:-0} + ${D_OTHER:-0}))
  fi

  # Tasks summary
  T_TOTAL=0
  T_TODO=0
  T_IP=0
  T_DONE=0
  T_BLOCKED=0

  if [ -f "$TASKS_FILE" ]; then
    T_TOTAL=$(jq '.tasks | length' "$TASKS_FILE" 2>/dev/null || echo 0)
    T_TODO=$(jq '[.tasks[] | select(.status == "todo")] | length' "$TASKS_FILE" 2>/dev/null || echo 0)
    T_IP=$(jq '[.tasks[] | select(.status == "in-progress")] | length' "$TASKS_FILE" 2>/dev/null || echo 0)
    T_DONE=$(jq '[.tasks[] | select(.status == "done")] | length' "$TASKS_FILE" 2>/dev/null || echo 0)
    T_BLOCKED=$(jq '[.tasks[] | select(.status == "blocked")] | length' "$TASKS_FILE" 2>/dev/null || echo 0)
  fi

  # Last activity
  LAST_MODIFIED=""
  for f in "$DECISIONS_FILE" "$TASKS_FILE"; do
    [ -f "$f" ] || continue
    local_ts=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    if [ -z "$LAST_MODIFIED" ] || [ "$local_ts" -gt "$LAST_MODIFIED" ] 2>/dev/null; then
      LAST_MODIFIED="$local_ts"
    fi
  done

  LAST_ACTIVITY="unknown"
  if [ -n "$LAST_MODIFIED" ] && [ "$LAST_MODIFIED" -gt 0 ] 2>/dev/null; then
    NOW_EPOCH=$(date +%s)
    DIFF=$((NOW_EPOCH - LAST_MODIFIED))
    if [ "$DIFF" -lt 3600 ]; then
      LAST_ACTIVITY="$((DIFF / 60))m ago"
    elif [ "$DIFF" -lt 86400 ]; then
      LAST_ACTIVITY="$((DIFF / 3600))h ago"
    else
      LAST_ACTIVITY="$((DIFF / 86400))d ago"
    fi
  fi

  PROJECT_JSON=$(jq -n \
    --arg name "$PROJECT_NAME" \
    --argjson decisionsTotal "$D_TOTAL" \
    --argjson decisionsResolved "$D_DONE" \
    --argjson decisionsUndecided "$D_UNDECIDED" \
    --argjson tasksTotal "$T_TOTAL" \
    --argjson tasksTodo "$T_TODO" \
    --argjson tasksInProgress "$T_IP" \
    --argjson tasksDone "$T_DONE" \
    --argjson tasksBlocked "$T_BLOCKED" \
    --arg lastActivity "$LAST_ACTIVITY" \
    '{
      name: $name,
      decisions: { total: $decisionsTotal, resolved: $decisionsResolved, undecided: $decisionsUndecided },
      tasks: { total: $tasksTotal, todo: $tasksTodo, inProgress: $tasksInProgress, done: $tasksDone, blocked: $tasksBlocked },
      lastActivity: $lastActivity
    }')
fi

# ── 3. Known issues ──
KNOWN_ISSUES_JSON='null'
KI_SNAPSHOT="${BASE}/bridge/known-issues.json"
if [ -f "$KI_SNAPSHOT" ]; then
  KI_COUNT=$(jq -r '.openCount // 0' "$KI_SNAPSHOT" 2>/dev/null)
  if [ "$KI_COUNT" -gt 0 ] 2>/dev/null; then
    KNOWN_ISSUES_JSON=$(jq '{
      openCount: .openCount,
      items: [.items[] | "\(.status): \(.title)"],
      updated: .updated
    }' "$KI_SNAPSHOT" 2>/dev/null || echo "null")
  fi
fi

# ── 4. Build combined card ──
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
  --arg type "project-card" \
  --arg ts "$TIMESTAMP" \
  --arg channel_id "${CHANNEL_ID:-}" \
  --arg channel_name "${CHANNEL_NAME:-}" \
  --arg project_name "${PROJECT_NAME:-}" \
  --argjson reactor "$REACTOR_JSON" \
  --argjson project "$PROJECT_JSON" \
  --argjson knownIssues "$KNOWN_ISSUES_JSON" \
  '{
    type: $type,
    timestamp: $ts,
    channelId: (if $channel_id != "" then $channel_id else null end),
    channelName: (if $channel_name != "" then $channel_name else null end),
    projectName: (if $project_name != "" then $project_name else null end),
    reactor: $reactor,
    project: $project
  } + (if $knownIssues != null then { knownIssues: $knownIssues } else {} end)'
