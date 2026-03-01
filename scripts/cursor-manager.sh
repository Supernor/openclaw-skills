#!/usr/bin/env bash
# cursor-manager.sh — Manage cursor files for delta-based skills
# Usage: cursor-manager.sh read <name>     # print current cursor value
#        cursor-manager.sh write <name>     # write current ISO timestamp
#        cursor-manager.sh reset <name>     # delete cursor (next run processes everything)
#        cursor-manager.sh list             # show all cursors and their values

set -eo pipefail

BASE="/home/node/.openclaw"
ACTION="${1:-}"
NAME="${2:-}"

# Known cursor files
declare -A CURSORS=(
  [github-feed]="$BASE/github-feed-cursor.txt"
  [upstream-feed]="$BASE/upstream-feed-cursor.txt"
  [changelog-post]="$BASE/changelog-post-cursor.txt"
  [model-health-notify]="$BASE/model-health-notify-cursor.txt"
)

resolve_path() {
  local name="$1"
  if [ -n "${CURSORS[$name]:-}" ]; then
    echo "${CURSORS[$name]}"
  else
    echo "$BASE/${name}-cursor.txt"
  fi
}

case "$ACTION" in
  read)
    [ -z "$NAME" ] && { echo '{"error":"Usage: cursor-manager.sh read <name>"}' | jq .; exit 1; }
    CFILE=$(resolve_path "$NAME")
    if [ -f "$CFILE" ]; then
      VALUE=$(cat "$CFILE")
      jq -n --arg name "$NAME" --arg value "$VALUE" --arg path "$CFILE" \
        '{name: $name, value: $value, path: $path}'
    else
      jq -n --arg name "$NAME" --arg path "$CFILE" \
        '{name: $name, value: null, path: $path, note: "cursor not initialized"}'
    fi
    ;;
  write)
    [ -z "$NAME" ] && { echo '{"error":"Usage: cursor-manager.sh write <name>"}' | jq .; exit 1; }
    CFILE=$(resolve_path "$NAME")
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "$NOW" > "$CFILE"
    jq -n --arg name "$NAME" --arg value "$NOW" --arg path "$CFILE" \
      '{name: $name, value: $value, path: $path, action: "written"}'
    ;;
  reset)
    [ -z "$NAME" ] && { echo '{"error":"Usage: cursor-manager.sh reset <name>"}' | jq .; exit 1; }
    CFILE=$(resolve_path "$NAME")
    if [ -f "$CFILE" ]; then
      rm "$CFILE"
      jq -n --arg name "$NAME" --arg path "$CFILE" \
        '{name: $name, path: $path, action: "deleted"}'
    else
      jq -n --arg name "$NAME" --arg path "$CFILE" \
        '{name: $name, path: $path, action: "already absent"}'
    fi
    ;;
  list)
    RESULT="[]"
    for name in "${!CURSORS[@]}"; do
      CFILE="${CURSORS[$name]}"
      if [ -f "$CFILE" ]; then
        VALUE=$(cat "$CFILE")
        STATUS="initialized"
      else
        VALUE="null"
        STATUS="missing"
      fi
      RESULT=$(echo "$RESULT" | jq \
        --arg n "$name" --arg v "$VALUE" --arg s "$STATUS" --arg p "$CFILE" \
        '. + [{name: $n, value: (if $v == "null" then null else $v end), status: $s, path: $p}]')
    done
    echo "$RESULT" | jq 'sort_by(.name)'
    ;;
  *)
    echo '{"error":"Usage: cursor-manager.sh <read|write|reset|list> [name]","cursors":["github-feed","upstream-feed","changelog-post","model-health-notify"]}' | jq .
    exit 1
    ;;
esac
