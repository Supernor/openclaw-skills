#!/bin/bash
# gateway-log-query.sh — Parse structured gateway JSON logs
# Usage: gateway-log-query.sh [OPTIONS]
#   --level LEVEL    Filter by log level (DEBUG|INFO|WARN|ERROR|FATAL)
#   --module MODULE  Filter by module/subsystem name
#   --since MINUTES  Only entries from last N minutes
#   --limit N        Max entries to return (default 20)
#   --errors         Shorthand for --level ERROR + --level FATAL
#   --models         Show model-related entries (auth, fallback, cooldown)
#   --summary        One-line-per-entry format instead of full JSON
set -euo pipefail

LOG_DIR="/tmp/openclaw"
TODAY=$(date -u +%Y-%m-%d)
LOG_FILE="$LOG_DIR/openclaw-$TODAY.log"

# Defaults
LEVEL_FILTER=""
MODULE_FILTER=""
SINCE_MINUTES=""
LIMIT=20
ERRORS_ONLY=false
MODELS_ONLY=false
SUMMARY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --level) LEVEL_FILTER="$2"; shift 2;;
    --module) MODULE_FILTER="$2"; shift 2;;
    --since) SINCE_MINUTES="$2"; shift 2;;
    --limit) LIMIT="$2"; shift 2;;
    --errors) ERRORS_ONLY=true; shift;;
    --models) MODELS_ONLY=true; shift;;
    --summary) SUMMARY=true; shift;;
    *) echo '{"error":"Unknown option: '"$1"'"}'; exit 1;;
  esac
done

if [ ! -f "$LOG_FILE" ]; then
  echo '{"error":"No log file for today","path":"'"$LOG_FILE"'"}'
  exit 1
fi

# Build jq filter
JQ_FILTER="."

if $ERRORS_ONLY; then
  JQ_FILTER="$JQ_FILTER | select(._meta.logLevelName == \"ERROR\" or ._meta.logLevelName == \"FATAL\" or ._meta.logLevelName == \"WARN\")"
elif [ -n "$LEVEL_FILTER" ]; then
  JQ_FILTER="$JQ_FILTER | select(._meta.logLevelName == \"$LEVEL_FILTER\")"
fi

if [ -n "$MODULE_FILTER" ]; then
  JQ_FILTER="$JQ_FILTER | select(._meta.name | tostring | test(\"$MODULE_FILTER\"; \"i\"))"
fi

if $MODELS_ONLY; then
  JQ_FILTER="$JQ_FILTER | select(.\"0\" | tostring | test(\"auth|model|fallback|cooldown|billing|rate.limit|disabled|quarantine\"; \"i\"))"
fi

if [ -n "$SINCE_MINUTES" ]; then
  CUTOFF=$(date -u -d "$SINCE_MINUTES minutes ago" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)
  JQ_FILTER="$JQ_FILTER | select(.time >= \"$CUTOFF\")"
fi

if $SUMMARY; then
  JQ_FILTER="$JQ_FILTER | {time: .time, level: ._meta.logLevelName, module: (._meta.name | tostring | split(\"}\") | last // ._meta.name), msg: (.\"0\" | tostring | .[0:120])}"
fi

# Execute query
tail -5000 "$LOG_FILE" | jq -c "$JQ_FILTER" 2>/dev/null | tail -"$LIMIT"

# Append metadata line
LINE_COUNT=$(wc -l < "$LOG_FILE")
FILE_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
echo '{"_meta":{"log_file":"'"$LOG_FILE"'","total_lines":'"$LINE_COUNT"',"file_bytes":'"$FILE_SIZE"',"query_limit":'"$LIMIT"'}}'
