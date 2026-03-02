#!/usr/bin/env bash
# agent-bus.sh — Inter-agent communication bus backed by SQLite
# Stores structured results, file references, and media references.
# Small payloads (<4KB) go inline. Large content goes to bus/results/.
# Media blobs go to bus/media/ with transcript/metadata inline.
#
# Usage:
#   agent-bus.sh post --from <agent> --for <agent|any> --type <type> [--task <id>] [--ttl <hours>] [--payload <json>]
#   agent-bus.sh post --from <agent> --for <agent|any> --type <type> --file <path> [--task <id>] [--ttl <hours>]
#   agent-bus.sh post --from <agent> --for <agent|any> --type media-ref --media <path> --transcript <text> [--task <id>]
#   agent-bus.sh read [--id <id>] [--task <id>] [--for <agent>] [--type <type>] [--limit N] [--resolve]
#   agent-bus.sh consume <id>
#   agent-bus.sh pending [--for <agent>]
#   agent-bus.sh cleanup [--dry-run]
#   agent-bus.sh stats

set -eo pipefail

BASE="/home/node/.openclaw"
if [ ! -d "$BASE" ] && [ -d "/root/.openclaw" ]; then
  BASE="/root/.openclaw"
fi

DB="${BASE}/ops.db"
BUS_RESULTS="${BASE}/bus/results"
BUS_MEDIA="${BASE}/bus/media"
INLINE_MAX=4096  # bytes — payloads larger than this get stored as files

mkdir -p "$BUS_RESULTS" "$BUS_MEDIA"

if [ ! -f "$DB" ]; then
  echo '{"error":"ops.db not found","path":"'"$DB"'"}' >&2
  exit 1
fi

sq() { sqlite3 -json "$DB" "$1" 2>/dev/null; }
sq_exec() { sqlite3 "$DB" "$1"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

escape_sql() {
  echo "$1" | sed "s/'/''/g"
}

CMD="${1:?Usage: agent-bus.sh <post|read|consume|pending|cleanup|stats>}"
shift

case "$CMD" in

  # ──── POST ────
  post)
    FROM="" FOR="any" TYPE="result" TASK="" TTL=24 PAYLOAD="" FILE="" MEDIA="" TRANSCRIPT=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --from) FROM="$2"; shift 2 ;;
        --for) FOR="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        --task) TASK="$2"; shift 2 ;;
        --ttl) TTL="$2"; shift 2 ;;
        --payload) PAYLOAD="$2"; shift 2 ;;
        --file) FILE="$2"; shift 2 ;;
        --media) MEDIA="$2"; shift 2 ;;
        --transcript) TRANSCRIPT="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    if [ -z "$FROM" ]; then
      echo '{"error":"--from is required"}' >&2; exit 1
    fi

    TS=$(now)

    # --- Media ref ---
    if [ -n "$MEDIA" ]; then
      TYPE="media-ref"
      FILENAME=$(basename "$MEDIA")
      DEST="${BUS_MEDIA}/${FILENAME}"
      if [ -f "$MEDIA" ] && [ "$MEDIA" != "$DEST" ]; then
        cp "$MEDIA" "$DEST"
      fi
      SIZE_KB=$(du -k "$DEST" 2>/dev/null | awk '{print $1}')
      MIME=$(file -b --mime-type "$DEST" 2>/dev/null || echo "application/octet-stream")
      PAYLOAD=$(jq -nc \
        --arg path "$DEST" \
        --arg filename "$FILENAME" \
        --arg mime "$MIME" \
        --arg transcript "$TRANSCRIPT" \
        --argjson size_kb "${SIZE_KB:-0}" \
        '{type:"media-ref",path:$path,filename:$filename,mime:$mime,size_kb:$size_kb,transcript:$transcript}')

    # --- File content (explicit) ---
    elif [ -n "$FILE" ]; then
      if [ ! -f "$FILE" ]; then
        echo '{"error":"file not found","path":"'"$FILE"'"}' >&2; exit 1
      fi
      TYPE="file-ref"
      FILENAME=$(basename "$FILE")
      DEST="${BUS_RESULTS}/${TASK:-notatask}-${FILENAME}"
      cp "$FILE" "$DEST"
      SIZE_KB=$(du -k "$DEST" 2>/dev/null | awk '{print $1}')
      PAYLOAD=$(jq -nc \
        --arg path "$DEST" \
        --arg filename "$FILENAME" \
        --argjson size_kb "${SIZE_KB:-0}" \
        '{type:"file-ref",path:$path,filename:$filename,size_kb:$size_kb}')

    # --- Inline payload (auto-promote to file if too large) ---
    elif [ -n "$PAYLOAD" ]; then
      PAYLOAD_SIZE=${#PAYLOAD}
      if [ "$PAYLOAD_SIZE" -gt "$INLINE_MAX" ]; then
        REF_FILE="${BUS_RESULTS}/${TASK:-auto}-$(date +%s).json"
        echo "$PAYLOAD" > "$REF_FILE"
        SIZE_KB=$(du -k "$REF_FILE" 2>/dev/null | awk '{print $1}')
        PAYLOAD=$(jq -nc \
          --arg path "$REF_FILE" \
          --argjson size_kb "${SIZE_KB:-0}" \
          --argjson original_size "$PAYLOAD_SIZE" \
          '{type:"file-ref",path:$path,size_kb:$size_kb,original_bytes:$original_size,auto_promoted:true}')
        TYPE="file-ref"
      fi
    else
      echo '{"error":"one of --payload, --file, or --media is required"}' >&2; exit 1
    fi

    TASK_SQL="NULL"
    [ -n "$TASK" ] && TASK_SQL="'$(escape_sql "$TASK")'"

    ID=$(sqlite3 "$DB" "INSERT INTO agent_results (task_id, from_agent, for_agent, type, payload, created_at, ttl_hours)
      VALUES ($TASK_SQL, '$(escape_sql "$FROM")', '$(escape_sql "$FOR")', '$(escape_sql "$TYPE")', '$(escape_sql "$PAYLOAD")', '$TS', $TTL);
      SELECT last_insert_rowid();")
    echo "{\"status\":\"ok\",\"id\":$ID,\"type\":\"$TYPE\",\"size\":${#PAYLOAD}}"
    ;;

  # ──── READ ────
  read)
    ID="" TASK="" FOR="" TYPE="" LIMIT=10 RESOLVE=false
    while [ $# -gt 0 ]; do
      case "$1" in
        --id) ID="$2"; shift 2 ;;
        --task) TASK="$2"; shift 2 ;;
        --for) FOR="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        --resolve) RESOLVE=true; shift ;;
        *) shift ;;
      esac
    done

    WHERE="consumed = 0"
    [ -n "$ID" ] && WHERE="id = $ID"
    [ -n "$TASK" ] && WHERE="$WHERE AND task_id = '$(escape_sql "$TASK")'"
    [ -n "$FOR" ] && WHERE="$WHERE AND (for_agent = '$(escape_sql "$FOR")' OR for_agent = 'any')"
    [ -n "$TYPE" ] && WHERE="$WHERE AND type = '$(escape_sql "$TYPE")'"

    RESULTS=$(sq "SELECT * FROM agent_results WHERE $WHERE ORDER BY created_at DESC LIMIT $LIMIT;")

    if [ "$RESOLVE" = true ] && [ -n "$RESULTS" ] && [ "$RESULTS" != "[]" ]; then
      # Resolve file-ref payloads inline
      echo "$RESULTS" | jq -c '.[]' | while IFS= read -r ROW; do
        ROW_TYPE=$(echo "$ROW" | jq -r '.type')
        if [ "$ROW_TYPE" = "file-ref" ]; then
          FILE_PATH=$(echo "$ROW" | jq -r '.payload' | jq -r '.path // empty')
          if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
            CONTENT=$(cat "$FILE_PATH")
            echo "$ROW" | jq --arg content "$CONTENT" '.resolved_content = $content'
          else
            echo "$ROW"
          fi
        elif [ "$ROW_TYPE" = "media-ref" ]; then
          # For media, include transcript but not binary
          echo "$ROW"
        else
          echo "$ROW"
        fi
      done | jq -s '.'
    else
      echo "$RESULTS"
    fi
    ;;

  # ──── CONSUME ────
  consume)
    ID="${1:?Usage: agent-bus.sh consume <id>}"
    sq_exec "UPDATE agent_results SET consumed = 1 WHERE id = $ID;"
    echo "{\"status\":\"ok\",\"id\":$ID,\"consumed\":true}"
    ;;

  # ──── PENDING ────
  pending)
    FOR=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --for) FOR="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    if [ -n "$FOR" ]; then
      sq "SELECT * FROM agent_results WHERE consumed = 0 AND (for_agent = '$(escape_sql "$FOR")' OR for_agent = 'any') ORDER BY created_at ASC;"
    else
      sq "SELECT * FROM agent_results WHERE consumed = 0 ORDER BY created_at ASC;"
    fi
    ;;

  # ──── CLEANUP ────
  cleanup)
    DRY_RUN=false
    [ "${1:-}" = "--dry-run" ] && DRY_RUN=true

    TS=$(now)

    # Find expired rows
    EXPIRED=$(sq "SELECT id, type, payload FROM agent_results WHERE consumed = 1 OR (datetime(created_at, '+' || ttl_hours || ' hours') < datetime('$TS'));")
    COUNT=$(echo "$EXPIRED" | jq 'length' 2>/dev/null || echo 0)

    if [ "$DRY_RUN" = true ]; then
      echo "{\"dry_run\":true,\"would_remove\":$COUNT}"
      exit 0
    fi

    # Delete referenced files
    FILES_REMOVED=0
    if [ "$COUNT" -gt 0 ] && [ "$EXPIRED" != "[]" ]; then
      echo "$EXPIRED" | jq -r '.[].payload' | while IFS= read -r PL; do
        FILE_PATH=$(echo "$PL" | jq -r '.path // empty' 2>/dev/null)
        if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
          rm -f "$FILE_PATH"
          FILES_REMOVED=$((FILES_REMOVED + 1))
        fi
      done
    fi

    # Delete rows
    sq_exec "DELETE FROM agent_results WHERE consumed = 1 OR (datetime(created_at, '+' || ttl_hours || ' hours') < datetime('$TS'));"

    # Also clean orphaned files older than 48h
    ORPHANS=0
    for DIR in "$BUS_RESULTS" "$BUS_MEDIA"; do
      if [ -d "$DIR" ]; then
        while IFS= read -r F; do
          [ -z "$F" ] && continue
          rm -f "$F"
          ORPHANS=$((ORPHANS + 1))
        done < <(find "$DIR" -type f -mmin +2880 2>/dev/null)
      fi
    done

    echo "{\"status\":\"ok\",\"rows_removed\":$COUNT,\"orphans_removed\":$ORPHANS}"
    ;;

  # ──── STATS ────
  stats)
    TOTAL=$(sq_exec "SELECT COUNT(*) FROM agent_results;")
    PENDING=$(sq_exec "SELECT COUNT(*) FROM agent_results WHERE consumed = 0;")
    CONSUMED=$(sq_exec "SELECT COUNT(*) FROM agent_results WHERE consumed = 1;")
    BY_TYPE=$(sq "SELECT type, COUNT(*) as count FROM agent_results GROUP BY type;" 2>/dev/null)
    [ -z "$BY_TYPE" ] && BY_TYPE="[]"
    BY_AGENT=$(sq "SELECT from_agent, COUNT(*) as sent, SUM(CASE WHEN consumed=1 THEN 1 ELSE 0 END) as consumed FROM agent_results GROUP BY from_agent;" 2>/dev/null)
    [ -z "$BY_AGENT" ] && BY_AGENT="[]"
    RESULTS_SIZE=$(du -sk "$BUS_RESULTS" 2>/dev/null | awk '{print $1}')
    [ -z "$RESULTS_SIZE" ] && RESULTS_SIZE=0
    MEDIA_SIZE=$(du -sk "$BUS_MEDIA" 2>/dev/null | awk '{print $1}')
    [ -z "$MEDIA_SIZE" ] && MEDIA_SIZE=0

    jq -nc \
      --argjson total "$TOTAL" \
      --argjson pending "$PENDING" \
      --argjson consumed "$CONSUMED" \
      --argjson by_type "$BY_TYPE" \
      --argjson by_agent "$BY_AGENT" \
      --argjson results_kb "${RESULTS_SIZE:-0}" \
      --argjson media_kb "${MEDIA_SIZE:-0}" \
      '{total:$total,pending:$pending,consumed:$consumed,by_type:$by_type,by_agent:$by_agent,storage:{results_kb:$results_kb,media_kb:$media_kb}}'
    ;;

  *)
    echo '{"error":"Unknown command: '"$CMD"'","usage":"agent-bus.sh <post|read|consume|pending|cleanup|stats>"}' >&2
    exit 1
    ;;
esac
