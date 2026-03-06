#!/usr/bin/env bash
# session-maintenance.sh — Reset sessions approaching context limits
#
# Runs via cron or manually. Resets sessions over 85% context usage.
# Uses gateway WebSocket directly for admin operations.
#
# Usage:
#   session-maintenance.sh              # auto-detect and reset
#   session-maintenance.sh --dry-run    # preview only

set -eo pipefail

DRY_RUN=false
THRESHOLD=85
COMPOSE_DIR="/root/openclaw"
MCP_DIR="/root/.openclaw/mcp-servers/openclaw-gateway"
LOG_DIR="/root/.openclaw/logs"
AGENTS=("relay" "main" "spec-projects" "spec-github" "spec-dev" "spec-reactor" "spec-browser" "spec-research" "spec-security" "spec-ops" "spec-design" "spec-systems" "spec-comms")

[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

# Log a load snapshot before any resets (feeds agent satisfaction data)
mkdir -p "$LOG_DIR"
/root/.openclaw/scripts/agent-load-snapshot.sh --json >> "$LOG_DIR/agent-load-history.jsonl" 2>/dev/null || true

bloated_keys=()

for agent in "${AGENTS[@]}"; do
  json=$(cd "$COMPOSE_DIR" && docker compose exec -T openclaw-gateway openclaw sessions --agent "$agent" --json 2>/dev/null | grep -v "level=warning")
  [ -z "$json" ] && continue

  # Find sessions over threshold
  while IFS=$'\t' read -r key pct tokens ctx; do
    [ -z "$key" ] && continue
    echo "  $agent: $key — ${pct}% ($tokens / $ctx tokens)"
    bloated_keys+=("$key")
  done < <(echo "$json" | jq -r --argjson t "$THRESHOLD" '
    .sessions // [] | .[] |
    select(.contextTokens > 0 and .totalTokens != null) |
    select((.totalTokens / .contextTokens * 100) > $t) |
    "\(.key)\t\(.totalTokens / .contextTokens * 100 | floor)\t\(.totalTokens)\t\(.contextTokens)"
  ' 2>/dev/null)
done

if [ ${#bloated_keys[@]} -eq 0 ]; then
  echo "All sessions under ${THRESHOLD}% context. Nothing to do."
  # Still run orphan cleanup
  cd "$COMPOSE_DIR" && docker compose exec -T openclaw-gateway openclaw sessions cleanup --all-agents --enforce --fix-missing 2>/dev/null | grep -v "level=warning" | tail -3
  exit 0
fi

echo ""
echo "Found ${#bloated_keys[@]} session(s) over ${THRESHOLD}%"

if [ "$DRY_RUN" = true ]; then
  echo "(dry-run — no changes)"
  exit 0
fi

# Reset via gateway WS
GATEWAY_TOKEN=$(grep OPENCLAW_GATEWAY_TOKEN "$COMPOSE_DIR/.env" 2>/dev/null | cut -d= -f2)
export OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN"
cd "$MCP_DIR"
node session-bulk-reset.js "${bloated_keys[@]}" 2>&1

echo ""
# Also run built-in cleanup for orphaned entries
cd "$COMPOSE_DIR" && docker compose exec -T openclaw-gateway openclaw sessions cleanup --all-agents --enforce --fix-missing 2>/dev/null | grep -v "level=warning" | tail -3
echo "Session maintenance complete."

# Log post-reset snapshot too (shows effect of maintenance)
/root/.openclaw/scripts/agent-load-snapshot.sh --json >> "$LOG_DIR/agent-load-history.jsonl" 2>/dev/null || true
