#!/usr/bin/env bash
# model-clear.sh — Clear quarantine/cooldown for a provider or all providers
# Usage: model-clear.sh <provider|all>
# Providers: anthropic, google, openrouter, openai-codex, all

set -eo pipefail

BASE="/home/node/.openclaw"
PROVIDER="${1:-}"

if [ -z "$PROVIDER" ]; then
  echo '{"error":"Usage: model-clear.sh <provider|all>","providers":["anthropic","google","openrouter","openai-codex","all"]}' | jq .
  exit 1
fi

VALID_PROVIDERS="anthropic google openrouter openai-codex all"
if ! echo "$VALID_PROVIDERS" | grep -qw "$PROVIDER"; then
  echo "{\"error\":\"Unknown provider: $PROVIDER\",\"valid\":[\"anthropic\",\"google\",\"openrouter\",\"openai-codex\",\"all\"]}" | jq .
  exit 1
fi

CLEARED=0
AGENTS_JSON="[]"

# Build jq filter based on provider
if [ "$PROVIDER" = "all" ]; then
  JQ_FILTER='
    .usageStats |= with_entries(
      .value |= (del(.cooldownUntil, .disabledUntil, .disabledReason, .failureCounts) | .errorCount = 0)
    )'
else
  JQ_FILTER="
    .usageStats |= with_entries(
      if (.key | startswith(\"${PROVIDER}:\"))
      then .value |= (del(.cooldownUntil, .disabledUntil, .disabledReason, .failureCounts) | .errorCount = 0)
      else .
      end
    )"
fi

# Clear auth profiles across all agents
for AGENT_DIR in "$BASE"/agents/*/agent; do
  [ -d "$AGENT_DIR" ] || continue
  AP="$AGENT_DIR/auth-profiles.json"
  [ -f "$AP" ] || continue
  AGENT_ID=$(basename "$(dirname "$AGENT_DIR")")

  # Check if any matching profiles have errors
  if [ "$PROVIDER" = "all" ]; then
    HAS_ERRORS=$(jq '[.usageStats // {} | to_entries[] | select(.value.errorCount > 0 or .value.cooldownUntil != null or .value.disabledUntil != null)] | length' "$AP" 2>/dev/null || echo 0)
  else
    HAS_ERRORS=$(jq "[.usageStats // {} | to_entries[] | select(.key | startswith(\"${PROVIDER}:\")) | select(.value.errorCount > 0 or .value.cooldownUntil != null or .value.disabledUntil != null)] | length" "$AP" 2>/dev/null || echo 0)
  fi

  if [ "$HAS_ERRORS" -gt 0 ]; then
    TMP=$(mktemp)
    jq "$JQ_FILTER" "$AP" > "$TMP" && mv "$TMP" "$AP"
    CLEARED=$((CLEARED + HAS_ERRORS))
    AGENTS_JSON=$(echo "$AGENTS_JSON" | jq --arg a "$AGENT_ID" '. + [$a]')
  fi
done

# Update model-health.json
HEALTH_FILE="$BASE/model-health.json"
if [ -f "$HEALTH_FILE" ]; then
  TMP=$(mktemp)
  if [ "$PROVIDER" = "all" ]; then
    jq '
      .providers |= with_entries(.value.status = "healthy" | .value.reason = "cleared") |
      .fallbackChain.quarantined = []
    ' "$HEALTH_FILE" > "$TMP" && mv "$TMP" "$HEALTH_FILE"
  else
    jq --arg p "$PROVIDER" '
      if .providers[$p] then .providers[$p].status = "healthy" | .providers[$p].reason = "cleared" else . end |
      .fallbackChain.quarantined = [.fallbackChain.quarantined[] | select(. != $p)]
    ' "$HEALTH_FILE" > "$TMP" && mv "$TMP" "$HEALTH_FILE"
  fi
fi

# Append notification
NOTIF_FILE="$BASE/model-health-notifications.jsonl"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "{\"ts\":\"$NOW\",\"type\":\"recovery\",\"provider\":\"$PROVIDER\",\"reason\":\"manual-clear\",\"message\":\"Provider $PROVIDER manually cleared by user\"}" >> "$NOTIF_FILE"

# Check if billing-related
BILLING_WARNING=false
if [ -f "$HEALTH_FILE" ] && [ "$PROVIDER" != "all" ]; then
  PREV_REASON=$(jq -r --arg p "$PROVIDER" '.providers[$p].reason // "unknown"' "$HEALTH_FILE" 2>/dev/null || echo "unknown")
  [ "$PREV_REASON" = "billing" ] && BILLING_WARNING=true
fi

# Output
AGENT_COUNT=$(echo "$AGENTS_JSON" | jq 'length')
jq -n \
  --arg provider "$PROVIDER" \
  --argjson cleared "$CLEARED" \
  --argjson agents "$AGENTS_JSON" \
  --argjson agentCount "$AGENT_COUNT" \
  --argjson billingWarning "$BILLING_WARNING" \
  '{
    status: "cleared",
    provider: $provider,
    profilesCleared: $cleared,
    agents: $agents,
    billingWarning: $billingWarning,
    message: (
      "Cleared quarantine for " + $provider + ": " + ($cleared | tostring) + " profiles reset across " + ($agentCount | tostring) + " agents"
      + if $billingWarning then ". WARNING: Credits may still be exhausted — provider will re-quarantine on next failure." else "" end
    )
  }'
