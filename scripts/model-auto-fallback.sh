#!/usr/bin/env bash
# model-auto-fallback.sh — Dynamically expand/contract fallback chain
# Usage: model-auto-fallback.sh check    # evaluate and act
# Usage: model-auto-fallback.sh status   # report current state

set -eo pipefail

BASE="/home/node/.openclaw"
HEALTH_FILE="$BASE/model-health.json"
CONFIG_FILE="$BASE/openclaw.json"
ACTION="${1:-check}"

if [ ! -f "$HEALTH_FILE" ]; then
  echo '{"error":"model-health.json not found","action":"none"}' | jq .
  exit 1
fi

# Emergency backup pool (all via openrouter)
BACKUP_MODELS='["openrouter/anthropic/claude-sonnet-4-5","openrouter/google/gemini-2.0-flash","openrouter/meta-llama/llama-4-maverick"]'

# Read current state
QUARANTINED=$(jq -r '.fallbackChain.quarantined // [] | length' "$HEALTH_FILE")
EMERGENCY=$(jq -r '.fallbackChain.emergency // [] | length' "$HEALTH_FILE")
QUARANTINED_LIST=$(jq -r '.fallbackChain.quarantined // [] | join(", ")' "$HEALTH_FILE")
EMERGENCY_LIST=$(jq -r '.fallbackChain.emergency // [] | join(", ")' "$HEALTH_FILE")

# Check if openrouter itself is quarantined
OR_QUARANTINED=$(jq -r '.providers.openrouter.status // "healthy"' "$HEALTH_FILE")

if [ "$ACTION" = "status" ]; then
  jq -n \
    --argjson quarantined "$QUARANTINED" \
    --arg quarantinedList "$QUARANTINED_LIST" \
    --argjson emergency "$EMERGENCY" \
    --arg emergencyList "$EMERGENCY_LIST" \
    --arg orStatus "$OR_QUARANTINED" \
    '{
      quarantinedCount: $quarantined,
      quarantined: $quarantinedList,
      emergencyCount: $emergency,
      emergencyModels: $emergencyList,
      openrouterStatus: $orStatus,
      action: "none"
    }'
  exit 0
fi

# === CHECK MODE ===

# Case 1: Need expansion (2+ quarantined, no emergency models yet)
if [ "$QUARANTINED" -ge 2 ] && [ "$EMERGENCY" -eq 0 ]; then
  # Check if openrouter is quarantined — can't add backups
  if [ "$OR_QUARANTINED" != "healthy" ]; then
    jq -n \
      --argjson quarantined "$QUARANTINED" \
      --arg quarantinedList "$QUARANTINED_LIST" \
      '{
        action: "blocked",
        reason: "openrouter quarantined — all backup models use openrouter",
        critical: true,
        quarantined: $quarantinedList,
        message: "CRITICAL: " + ($quarantined | tostring) + " providers quarantined and openrouter is down — no backup models available"
      }'
    exit 0
  fi

  # Filter backup models to only healthy providers
  HEALTHY_BACKUPS=$(jq -n --argjson pool "$BACKUP_MODELS" '$pool')

  # Back up config
  cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

  # Add emergency models to openclaw.json fallbacks
  TMP=$(mktemp)
  jq --argjson backups "$HEALTHY_BACKUPS" '
    .agents.defaults.model.fallbacks = (.agents.defaults.model.fallbacks + $backups | unique)
  ' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"

  # Track in model-health.json
  TMP=$(mktemp)
  jq --argjson backups "$HEALTHY_BACKUPS" '
    .fallbackChain.emergency = $backups
  ' "$HEALTH_FILE" > "$TMP" && mv "$TMP" "$HEALTH_FILE"

  ADDED=$(echo "$HEALTHY_BACKUPS" | jq -r 'join(", ")')
  jq -n \
    --arg added "$ADDED" \
    --argjson count "$(echo "$HEALTHY_BACKUPS" | jq 'length')" \
    --arg quarantined "$QUARANTINED_LIST" \
    '{
      action: "expanded",
      modelsAdded: $added,
      count: $count,
      quarantined: $quarantined,
      restartRequired: true,
      message: "Fallback chain expanded: added " + ($count | tostring) + " emergency models. Restart required."
    }'
  exit 0
fi

# Case 2: Need contraction (emergency models exist, quarantine resolved)
if [ "$EMERGENCY" -gt 0 ] && [ "$QUARANTINED" -lt 2 ]; then
  EMERGENCY_MODELS=$(jq '.fallbackChain.emergency // []' "$HEALTH_FILE")

  # Back up config
  cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

  # Remove emergency models from openclaw.json
  TMP=$(mktemp)
  jq --argjson remove "$EMERGENCY_MODELS" '
    .agents.defaults.model.fallbacks = [.agents.defaults.model.fallbacks[] | select(. as $m | $remove | index($m) | not)]
  ' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"

  # Clear emergency from model-health.json
  TMP=$(mktemp)
  jq 'del(.fallbackChain.emergency)' "$HEALTH_FILE" > "$TMP" && mv "$TMP" "$HEALTH_FILE"

  jq -n \
    --arg removed "$EMERGENCY_LIST" \
    --argjson count "$EMERGENCY" \
    '{
      action: "contracted",
      modelsRemoved: $removed,
      count: $count,
      restartRequired: true,
      message: "Fallback chain restored: removed " + ($count | tostring) + " emergency models. Restart required."
    }'
  exit 0
fi

# Case 3: No action needed
jq -n \
  --argjson quarantined "$QUARANTINED" \
  --argjson emergency "$EMERGENCY" \
  '{
    action: "none",
    quarantinedCount: $quarantined,
    emergencyCount: $emergency,
    message: "No action needed"
  }'
