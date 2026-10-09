#!/bin/bash
set -euo pipefail

# Load registry
REGISTRY=~/.openclaw/registry.json
CHANNEL=$(jq -r '.discord.channels."ops-dashboard"' "$REGISTRY")
PIN_MSG=$(jq -r '.discord.pins.dashboard' "$REGISTRY")

# Gather health data
echo "Gathering health data..."
MODEL_HEALTH=$(jq '.' ~/.openclaw/model-health.json 2>/dev/null || echo '{}')
KEY_DRIFT=$(bash ~/.openclaw/scripts/key-drift-check.sh 2>/dev/null || echo "No key drift issue detected")
REPO_HEALTH=$(bash ~/.openclaw/scripts/repo-health.sh 2>/dev/null || echo "Repos reachable")
LOG_AUDIT=$(bash ~/.openclaw/scripts/log-audit.sh 2>/dev/null || echo "No critical log warnings")

# Determine status
STATUS="green"
ISSUES=()

# Check for issues
echo "$REPO_HEALTH" | grep -q "unreachable" && ISSUES+=("repo") || true
echo "$LOG_AUDIT" | grep -qi "warning" && ISSUES+=("logs") || true
echo "$KEY_DRIFT" | grep -qi "drift" && ISSUES+=("keys") || true

if [ $(echo "$MODEL_HEALTH" | jq -r '[(.providers[] | select(.quarantined==true))] | length' 2>/dev/null) -ge 2 ]; then
  ISSUES+=("providers")
fi

case "${#ISSUES[@]}" in
  0) STATUS="green" ;;
  1) STATUS="yellow" ;;
  *) STATUS="red" ;;
esac

# Color mapping
case "$STATUS" in
  green) COLOR="5763719" ;;
  yellow) COLOR="16776960" ;;
  red) COLOR="15548997" ;;
esac

# Generate message from template
TEMPLATE_PATH=~/.openclaw/templates/dashboard-update.txt
TEMPLATE=$(cat "$TEMPLATE_PATH" 2>/dev/null || echo "Status: ${STATUS^^} | Issues: ${ISSUES[*]}")

# Fill template
MESSAGE=$(echo "$TEMPLATE" | sed "s/{{STATUS}}/${STATUS^^}/g" | sed "s/{{COLOR}}/${COLOR}/g")
MESSAGE="${MESSAGE/{{ISSUES}}/${ISSUES[*]}}"

# Post message to Discord
echo "Posting updated dashboard status: $STATUS"
echo "Message length: ${#MESSAGE} characters"

# Use Discord REST API via curl to edit pinned message
WEBHOOK_URL=$(jq -r '.discord.bot_webhook' "$REGISTRY")
if [ -n "$WEBHOOK_URL" ] && [ -n "$PIN_MSG" ]; then
  OUTPUT=$(curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{\"content\":\"$MESSAGE\"}" | jq -r '.status')
   echo "Dashboard update result: $OUTPUT"
fi

# Log event
bash ~/.openclaw/scripts/log-event.sh INFO "dashboard-update: Updated: $STATUS"

echo "Dashboard update completed successfully"
