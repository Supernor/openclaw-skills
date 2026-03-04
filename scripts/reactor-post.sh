#!/usr/bin/env bash
# reactor-post.sh — Post status updates to #ops-reactor Discord channel
# Usage: reactor-post.sh "message"
# Usage: reactor-post.sh --embed "title" "description"
#
# Called by Claude Code to broadcast status updates visible in Discord.

set -eo pipefail

WEBHOOK_URL=$(cat /root/.openclaw/reactor-webhook-url.txt 2>/dev/null)
if [ -z "$WEBHOOK_URL" ]; then
  echo '{"error":"Webhook URL not found at /root/.openclaw/reactor-webhook-url.txt"}'
  exit 1
fi

MODE="${1:?Usage: reactor-post.sh <message> OR reactor-post.sh --embed <title> <description>}"

if [ "$MODE" = "--embed" ]; then
  TITLE="${2:?Usage: reactor-post.sh --embed <title> <description>}"
  DESC="${3:-}"
  # Embed with timestamp
  PAYLOAD=$(jq -n \
    --arg title "$TITLE" \
    --arg desc "$DESC" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      username: "Reactor",
      embeds: [{
        title: $title,
        description: $desc,
        color: 5814783,
        footer: {text: "Claude Code"},
        timestamp: $ts
      }]
    }')
else
  # Simple message
  MSG="$*"
  PAYLOAD=$(jq -n --arg msg "$MSG" '{username: "Reactor", content: $msg}')
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$WEBHOOK_URL")

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo '{"status":"ok","channel":"ops-reactor"}'
else
  echo "{\"status\":\"error\",\"http_code\":$HTTP_CODE}"
  exit 1
fi
