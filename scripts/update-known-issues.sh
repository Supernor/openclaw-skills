#!/usr/bin/env bash
# update-known-issues.sh — Refresh known-issues snapshot from Chartroom
# Queries the governance-known-issues chart via LanceDB, extracts open items,
# writes a lightweight JSON snapshot for reactor-summary.sh and nightly reports.
#
# Usage:
#   update-known-issues.sh              # Refresh snapshot
#   update-known-issues.sh --check      # Exit 0 if open issues exist, 1 if clear
#
# Output: /root/.openclaw/bridge/known-issues.json
# {
#   "chartId": "<id>",
#   "updated": "<iso>",
#   "openCount": N,
#   "items": [ { "num": 1, "status": "OPEN", "title": "..." }, ... ]
# }

set -eo pipefail

BASE="/root/.openclaw"
SNAPSHOT="${BASE}/bridge/known-issues.json"
COMPOSE_DIR="/root/openclaw"
CHART_SEARCH_TERM="governance-known-issues-openclaw-installation"

mkdir -p "$(dirname "$SNAPSHOT")"

# Query chartroom for the known-issues chart
RAW=$(docker compose -f "${COMPOSE_DIR}/docker-compose.yml" exec -T openclaw-gateway \
  openclaw ltm search "$CHART_SEARCH_TERM" 2>&1 | tail -n +2)

# Extract the chart entry (first result that matches our chart name pattern)
CHART_TEXT=$(echo "$RAW" | jq -r '
  [ .[] | select(.text | test("governance-known-issues")) ] | .[0].text // empty
' 2>/dev/null)

CHART_ID=$(echo "$RAW" | jq -r '
  [ .[] | select(.text | test("governance-known-issues")) ] | .[0].id // empty
' 2>/dev/null)

if [ -z "$CHART_TEXT" ]; then
  # Chart not found — write empty snapshot
  jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{ chartId: null, updated: $ts, openCount: 0, items: [], note: "chart not found" }' \
    > "$SNAPSHOT"
  [ "${1:-}" = "--check" ] && exit 1
  exit 0
fi

# Parse open items from chart text
# Format: "N) STATUS -- title..." where STATUS is OPEN, PARTIALLY RESOLVED, BY DESIGN, CLOSED
# Extract lines matching numbered items with actionable statuses
ITEMS_JSON=$(echo "$CHART_TEXT" | grep -oP '\d+\)\s+(OPEN|PARTIALLY RESOLVED)\s+[—–-]+\s+\K.*?(?=\.\s+WHAT BROKE|\s+WHAT BROKE|$)' | head -20 | \
  awk 'BEGIN { printf "[" }
    NR > 1 { printf "," }
    { gsub(/"/, "\\\""); printf "{\"title\":\"%s\"}", $0 }
  END { printf "]" }' 2>/dev/null || echo "[]")

# Also extract the status for each numbered item
ITEMS_WITH_STATUS=$(echo "$CHART_TEXT" | grep -oP '\d+\)\s+(OPEN|PARTIALLY RESOLVED)\s+[—–-]+\s+.*?(?=\.\s+WHAT BROKE|\s+WHAT BROKE|\s+\d+\)|$)' | head -20)

# Build proper items array with jq
ITEMS="[]"
if [ -n "$ITEMS_WITH_STATUS" ]; then
  ITEMS=$(echo "$ITEMS_WITH_STATUS" | while IFS= read -r line; do
    NUM=$(echo "$line" | grep -oP '^\d+')
    STATUS=$(echo "$line" | grep -oP '(OPEN|PARTIALLY RESOLVED)')
    TITLE=$(echo "$line" | sed -E 's/^[0-9]+\)\s+(OPEN|PARTIALLY RESOLVED)\s+[—–-]+\s+//')
    jq -n --arg num "$NUM" --arg status "$STATUS" --arg title "$TITLE" \
      '{ num: ($num | tonumber), status: $status, title: $title }'
  done | jq -s '.')
fi

OPEN_COUNT=$(echo "$ITEMS" | jq 'length')

# Write snapshot
jq -n \
  --arg chartId "$CHART_ID" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson openCount "${OPEN_COUNT:-0}" \
  --argjson items "$ITEMS" \
  '{ chartId: $chartId, updated: $ts, openCount: $openCount, items: $items }' \
  > "$SNAPSHOT"

# --check mode: exit 0 if open issues, 1 if clear
if [ "${1:-}" = "--check" ]; then
  [ "$OPEN_COUNT" -gt 0 ] && exit 0 || exit 1
fi

echo "Snapshot written: ${OPEN_COUNT} open items -> ${SNAPSHOT}"
