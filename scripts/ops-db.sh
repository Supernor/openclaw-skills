#!/usr/bin/env bash
# ops-db.sh — Query/mutate the OpenClaw operational database
# Both Claude Code (host) and agents (container) use this script.
# All output is JSON for easy piping.
#
# Usage:
#   ops-db.sh health snapshot                     # Record current provider health
#   ops-db.sh health latest                       # Latest status per provider
#   ops-db.sh health history [provider] [--limit N]  # Recent snapshots
#
#   ops-db.sh incident open <title> [--provider X] [--severity X] [--desc "..."]
#   ops-db.sh incident close <id> [--resolution "..."]
#   ops-db.sh incident list [--open|--all]
#
#   ops-db.sh task create <agent> <summary> [--urgency X] [--context "..."] [--files '["..."]']
#   ops-db.sh task update <id> <status> [--result '{"..."}']
#   ops-db.sh task list [--status X] [--agent X]
#   ops-db.sh task get <id>
#
#   ops-db.sh notify <type> <provider> <message> [--reason X]
#   ops-db.sh notify list [--undelivered|--all] [--limit N]
#   ops-db.sh notify deliver <id>
#
#   ops-db.sh config log <json_line>              # Backfill a config-audit entry
#   ops-db.sh config recent [--limit N]
#
#   ops-db.sh kv get <key>
#   ops-db.sh kv set <key> <value>
#
#   ops-db.sh query "<SQL>"                       # Raw query (SELECT only)
#   ops-db.sh stats                               # Table row counts
#   ops-db.sh init                                # Re-initialize schema (safe, uses IF NOT EXISTS)

set -eo pipefail

BASE="/home/node/.openclaw"
DB="${BASE}/ops.db"
INIT_SQL="${BASE}/scripts/ops-db-init.sql"

# If running on host (Claude Code), check alternate path
if [ ! -d "$BASE" ] && [ -d "/root/.openclaw" ]; then
  BASE="/root/.openclaw"
  DB="${BASE}/ops.db"
  INIT_SQL="${BASE}/scripts/ops-db-init.sql"
fi

# Auto-init if DB doesn't exist
if [ ! -f "$DB" ] && [ -f "$INIT_SQL" ]; then
  sqlite3 "$DB" < "$INIT_SQL"
fi

if [ ! -f "$DB" ]; then
  echo '{"error":"ops.db not found","path":"'"$DB"'"}' >&2
  exit 1
fi

sq() {
  sqlite3 -json "$DB" "$1"
}

sq_exec() {
  sqlite3 "$DB" "$1"
}

# Insert and return the inserted row as JSON
# Usage: sq_insert_return <table> <insert_sql>
sq_insert_return() {
  local TABLE="$1" SQL="$2"
  sqlite3 -json "$DB" "$SQL; SELECT * FROM $TABLE WHERE rowid = last_insert_rowid();"
}

CMD="${1:?Usage: ops-db.sh <health|incident|task|notify|config|kv|query|stats|init>}"
SUB="${2:-}"

case "$CMD" in

  # ──── HEALTH ────
  health)
    case "$SUB" in
      snapshot)
        # Read current model-health.json and insert snapshots
        MH="${BASE}/model-health.json"
        if [ ! -f "$MH" ]; then
          echo '{"error":"model-health.json not found"}'
          exit 1
        fi
        NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        COUNT=0
        for PROVIDER in $(jq -r '.providers | keys[]' "$MH"); do
          STATUS=$(jq -r ".providers[\"$PROVIDER\"].status" "$MH")
          REASON=$(jq -r ".providers[\"$PROVIDER\"].reason // \"none\"" "$MH")
          FCOUNT=$(jq -r ".providers[\"$PROVIDER\"].failureCount // 0" "$MH")
          # Get first profile's error count and last used
          ECOUNT=$(jq -r "[.providers[\"$PROVIDER\"].profiles[]] | first | .errorCount // 0" "$MH")
          LUSED=$(jq -r "[.providers[\"$PROVIDER\"].profiles[]] | first | .lastUsed // \"\"" "$MH")
          sq_exec "INSERT INTO health_snapshots (ts, provider, status, reason, failure_count, error_count, last_used) VALUES ('$NOW', '$PROVIDER', '$STATUS', '$REASON', $FCOUNT, $ECOUNT, '$LUSED');"
          COUNT=$((COUNT + 1))
        done
        echo "{\"status\":\"ok\",\"inserted\":$COUNT,\"timestamp\":\"$NOW\"}"
        ;;
      latest)
        sq "SELECT * FROM v_latest_health;"
        ;;
      history)
        PROVIDER="${3:-}"
        LIMIT=20
        shift 2 2>/dev/null || true
        while [ $# -gt 0 ]; do
          case "$1" in
            --limit) LIMIT="$2"; shift 2 ;;
            *) PROVIDER="$1"; shift ;;
          esac
        done
        if [ -n "$PROVIDER" ]; then
          sq "SELECT * FROM health_snapshots WHERE provider='$PROVIDER' ORDER BY ts DESC LIMIT $LIMIT;"
        else
          sq "SELECT * FROM health_snapshots ORDER BY ts DESC LIMIT $LIMIT;"
        fi
        ;;
      *) echo '{"error":"Usage: ops-db.sh health <snapshot|latest|history>"}'; exit 1 ;;
    esac
    ;;

  # ──── INCIDENTS ────
  incident)
    case "$SUB" in
      open)
        TITLE="${3:?Usage: ops-db.sh incident open <title>}"
        PROVIDER="" SEVERITY="medium" DESC=""
        shift 3
        while [ $# -gt 0 ]; do
          case "$1" in
            --provider) PROVIDER="$2"; shift 2 ;;
            --severity) SEVERITY="$2"; shift 2 ;;
            --desc) DESC="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        sq_insert_return incidents "INSERT INTO incidents (provider, severity, title, description) VALUES ('$PROVIDER', '$SEVERITY', '$(echo "$TITLE" | sed "s/'/''/g")', '$(echo "$DESC" | sed "s/'/''/g")')"
        ;;
      close)
        ID="${3:?Usage: ops-db.sh incident close <id>}"
        RES=""
        [ "${4:-}" = "--resolution" ] && RES="$5"
        sq "UPDATE incidents SET closed_at=strftime('%Y-%m-%dT%H:%M:%SZ','now'), resolution='$(echo "$RES" | sed "s/'/''/g")' WHERE id=$ID; SELECT * FROM incidents WHERE id=$ID;"
        ;;
      list)
        FLAG="${3:---open}"
        case "$FLAG" in
          --open) sq "SELECT * FROM v_open_incidents;" ;;
          --all)  sq "SELECT * FROM incidents ORDER BY opened_at DESC LIMIT 50;" ;;
          *)      sq "SELECT * FROM v_open_incidents;" ;;
        esac
        ;;
      *) echo '{"error":"Usage: ops-db.sh incident <open|close|list>"}'; exit 1 ;;
    esac
    ;;

  # ──── TASKS ────
  task)
    case "$SUB" in
      create)
        AGENT="${3:?Usage: ops-db.sh task create <agent> <summary>}"
        TASK="${4:?Usage: ops-db.sh task create <agent> <summary>}"
        URGENCY="routine" CONTEXT="" FILES="" ERRORS="" OUTCOME=""
        shift 4
        while [ $# -gt 0 ]; do
          case "$1" in
            --urgency) URGENCY="$2"; shift 2 ;;
            --context) CONTEXT="$2"; shift 2 ;;
            --files) FILES="$2"; shift 2 ;;
            --errors) ERRORS="$2"; shift 2 ;;
            --outcome) OUTCOME="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        sq_insert_return tasks "INSERT INTO tasks (agent, urgency, task, context, files, errors, outcome) VALUES ('$AGENT', '$URGENCY', '$(echo "$TASK" | sed "s/'/''/g")', '$(echo "$CONTEXT" | sed "s/'/''/g")', '$(echo "$FILES" | sed "s/'/''/g")', '$(echo "$ERRORS" | sed "s/'/''/g")', '$(echo "$OUTCOME" | sed "s/'/''/g")')"
        ;;
      update)
        ID="${3:?Usage: ops-db.sh task update <id> <status>}"
        STATUS="${4:?Usage: ops-db.sh task update <id> <status>}"
        RESULT=""
        [ "${5:-}" = "--result" ] && RESULT="$6"
        sq "UPDATE tasks SET status='$STATUS', updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now'), result='$(echo "$RESULT" | sed "s/'/''/g")' WHERE id=$ID; SELECT * FROM tasks WHERE id=$ID;"
        ;;
      list)
        FILTER_STATUS="" FILTER_AGENT=""
        shift 2 2>/dev/null || true
        while [ $# -gt 0 ]; do
          case "$1" in
            --status) FILTER_STATUS="$2"; shift 2 ;;
            --agent) FILTER_AGENT="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        WHERE=""
        if [ -n "$FILTER_STATUS" ]; then WHERE="WHERE status='$FILTER_STATUS'"; fi
        if [ -n "$FILTER_AGENT" ]; then
          if [ -n "$WHERE" ]; then WHERE="$WHERE AND agent='$FILTER_AGENT'"
          else WHERE="WHERE agent='$FILTER_AGENT'"; fi
        fi
        if [ -z "$WHERE" ]; then
          sq "SELECT * FROM v_pending_tasks;"
        else
          sq "SELECT * FROM tasks $WHERE ORDER BY created_at DESC LIMIT 50;"
        fi
        ;;
      get)
        ID="${3:?Usage: ops-db.sh task get <id>}"
        sq "SELECT * FROM tasks WHERE id=$ID;"
        ;;
      *) echo '{"error":"Usage: ops-db.sh task <create|update|list|get>"}'; exit 1 ;;
    esac
    ;;

  # ──── NOTIFICATIONS ────
  notify)
    if [ "$SUB" = "list" ]; then
      FLAG="${3:---undelivered}" LIMIT=20
      shift 2 2>/dev/null || true
      while [ $# -gt 0 ]; do
        case "$1" in
          --undelivered) FLAG="--undelivered"; shift ;;
          --all) FLAG="--all"; shift ;;
          --limit) LIMIT="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      case "$FLAG" in
        --undelivered) sq "SELECT * FROM v_undelivered_notifications LIMIT $LIMIT;" ;;
        --all) sq "SELECT * FROM notifications ORDER BY ts DESC LIMIT $LIMIT;" ;;
      esac
    elif [ "$SUB" = "deliver" ]; then
      ID="${3:?Usage: ops-db.sh notify deliver <id>}"
      sq_exec "UPDATE notifications SET delivered=1 WHERE id=$ID;"
      echo "{\"status\":\"ok\",\"id\":$ID}"
    else
      # ops-db.sh notify <type> <provider> <message> [--reason X]
      TYPE="${SUB:?Usage: ops-db.sh notify <type> <provider> <message>}"
      PROVIDER="${3:?}"
      MESSAGE="${4:?}"
      REASON=""
      [ "${5:-}" = "--reason" ] && REASON="$6"
      sq_insert_return notifications "INSERT INTO notifications (type, provider, reason, message) VALUES ('$TYPE', '$PROVIDER', '$REASON', '$(echo "$MESSAGE" | sed "s/'/''/g")')"
    fi
    ;;

  # ──── CONFIG ────
  config)
    case "$SUB" in
      log)
        LINE="${3:?Usage: ops-db.sh config log '<json>'}"
        TS=$(echo "$LINE" | jq -r '.ts')
        SOURCE=$(echo "$LINE" | jq -r '.source // ""')
        EVENT=$(echo "$LINE" | jq -r '.event // ""')
        PHASH=$(echo "$LINE" | jq -r '.previousHash // ""')
        NHASH=$(echo "$LINE" | jq -r '.nextHash // ""')
        PBYTES=$(echo "$LINE" | jq -r '.previousBytes // "null"')
        NBYTES=$(echo "$LINE" | jq -r '.nextBytes // "null"')
        GMODE=$(echo "$LINE" | jq -r '.gatewayModeAfter // ""')
        SUSP=$(echo "$LINE" | jq -c '.suspicious // []')
        RESULT=$(echo "$LINE" | jq -r '.result // ""')
        sq_exec "INSERT INTO config_changes (ts, source, event, previous_hash, next_hash, previous_bytes, next_bytes, gateway_mode, suspicious, result) VALUES ('$TS', '$SOURCE', '$EVENT', '$PHASH', '$NHASH', $PBYTES, $NBYTES, '$GMODE', '$SUSP', '$RESULT');"
        echo '{"status":"ok","ts":"'"$TS"'"}'
        ;;
      recent)
        LIMIT=20
        [ "${3:-}" = "--limit" ] && LIMIT="$4"
        sq "SELECT * FROM config_changes ORDER BY ts DESC LIMIT $LIMIT;"
        ;;
      *) echo '{"error":"Usage: ops-db.sh config <log|recent>"}'; exit 1 ;;
    esac
    ;;

  # ──── KV ────
  kv)
    case "$SUB" in
      get)
        KEY="${3:?Usage: ops-db.sh kv get <key>}"
        RESULT=$(sq_exec "SELECT value FROM kv WHERE key='$KEY';")
        if [ -n "$RESULT" ]; then
          echo "{\"key\":\"$KEY\",\"value\":\"$RESULT\"}"
        else
          echo "{\"key\":\"$KEY\",\"value\":null}"
        fi
        ;;
      set)
        KEY="${3:?Usage: ops-db.sh kv set <key> <value>}"
        VALUE="${4:?}"
        sq_exec "INSERT OR REPLACE INTO kv (key, value, updated_at) VALUES ('$KEY', '$(echo "$VALUE" | sed "s/'/''/g")', strftime('%Y-%m-%dT%H:%M:%SZ','now'));"
        echo "{\"status\":\"ok\",\"key\":\"$KEY\"}"
        ;;
      *) echo '{"error":"Usage: ops-db.sh kv <get|set>"}'; exit 1 ;;
    esac
    ;;

  # ──── RAW QUERY ────
  query)
    SQL="${SUB:?Usage: ops-db.sh query '<SELECT ...>'}"
    # Safety: only allow SELECT
    if echo "$SQL" | grep -iqE '^\s*(insert|update|delete|drop|alter|create)'; then
      echo '{"error":"Only SELECT queries allowed via query command"}' >&2
      exit 1
    fi
    sq "$SQL"
    ;;

  # ──── STATS ────
  stats)
    echo "{"
    for TABLE in health_snapshots config_changes incidents tasks notifications kv; do
      COUNT=$(sq_exec "SELECT COUNT(*) FROM $TABLE;")
      echo "  \"$TABLE\": $COUNT,"
    done
    SIZE=$(du -k "$DB" 2>/dev/null | awk '{print $1}')
    echo "  \"db_size_kb\": $SIZE"
    echo "}"
    ;;

  # ──── INIT ────
  init)
    if [ -f "$INIT_SQL" ]; then
      sqlite3 "$DB" < "$INIT_SQL"
      echo '{"status":"ok","message":"schema initialized"}'
    else
      echo '{"error":"init SQL not found at '"$INIT_SQL"'"}'
      exit 1
    fi
    ;;

  *)
    echo '{"error":"Unknown command: '"$CMD"'","usage":"ops-db.sh <health|incident|task|notify|config|kv|query|stats|init>"}' >&2
    exit 1
    ;;
esac
