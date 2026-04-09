#!/usr/bin/env bash
# Alignment: unified Discord posting script for CLI activity channels.
# Role: post status updates to the correct ops channel based on engine type.
# Dependencies: webhook URLs at /root/.openclaw/<channel>-webhook-url.txt.
# Key patterns: channel selection by engine name. Same interface as reactor-post.sh
# but routes to ops-codex, ops-gemini, ops-gateway, or ops-reactor based on --channel flag.
# Usage: ops-post.sh --channel codex "message"
#        ops-post.sh --channel gemini --embed "title" "description"
# Reference: /root/.openclaw/docs/policy-context-injection.md

set -eo pipefail

# Parse channel flag
CHANNEL="reactor"  # default
if [ "$1" = "--channel" ]; then
    CHANNEL="$2"
    shift 2
fi

# Resolve webhook URL
WEBHOOK_FILE="/root/.openclaw/ops-${CHANNEL}-webhook-url.txt"
# Fallback: reactor uses the old filename
if [ "$CHANNEL" = "reactor" ]; then
    WEBHOOK_FILE="/root/.openclaw/reactor-webhook-url.txt"
fi

WEBHOOK_URL=$(cat "$WEBHOOK_FILE" 2>/dev/null)
if [ -z "$WEBHOOK_URL" ]; then
    echo "{\"error\":\"No webhook for channel ops-${CHANNEL}. Expected: ${WEBHOOK_FILE}\"}"
    exit 1
fi

# Bot name per channel
NAMES='{"codex":"Codex","gemini":"Gemini","gateway":"Gateway","reactor":"Reactor"}'
BOT_NAME=$(echo "$NAMES" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$CHANNEL','OpenClaw'))" 2>/dev/null || echo "OpenClaw")

MODE="${1:?Usage: ops-post.sh [--channel name] <message> OR --embed <title> <description>}"

if [ "$MODE" = "--embed" ]; then
    TITLE="${2:?Usage: ops-post.sh --embed <title> <description>}"
    DESC="${3:-}"
    PAYLOAD=$(jq -n \
        --arg title "$TITLE" \
        --arg desc "$DESC" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg bot "$BOT_NAME" \
        '{
            username: $bot,
            embeds: [{
                title: $title,
                description: $desc,
                timestamp: $ts,
                color: 3447003
            }]
        }')
else
    PAYLOAD=$(jq -n --arg msg "$MODE" --arg bot "$BOT_NAME" '{username: $bot, content: $msg}')
fi

curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" > /dev/null 2>&1

echo "{\"status\":\"ok\",\"channel\":\"ops-${CHANNEL}\"}"
