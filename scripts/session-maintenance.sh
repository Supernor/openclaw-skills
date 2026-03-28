#!/usr/bin/env bash
# session-maintenance.sh — Reset sessions approaching context limits
#
# Runs via cron or manually. Resets sessions over 85% context usage.
# Uses gateway WebSocket directly for admin operations.
#
# Usage:
#   session-maintenance.sh              # auto-detect and reset
#   session-maintenance.sh --dry-run    # preview only
#
# Environment detection:
#   Host: uses docker compose exec to reach gateway
#   Container: uses openclaw CLI directly (no docker/compose needed)

set -eo pipefail

DRY_RUN=false
THRESHOLD=85

# --- Environment detection ---
# Host context: docker compose available AND compose file exists
# Container context: everything else (OPENCLAW_HOME override, no docker, /.dockerenv)
OPENCLAW_COMPOSE_DIR="${OPENCLAW_COMPOSE_DIR:-/root/openclaw}"
if [ -f "/.dockerenv" ] || [ -n "${OPENCLAW_HOME:-}" ] || ! command -v docker &>/dev/null || [ ! -f "$OPENCLAW_COMPOSE_DIR/docker-compose.yml" ]; then
  IN_CONTAINER=true
  OPENCLAW_HOME="${OPENCLAW_HOME:-/home/node/.openclaw}"
  COMPOSE_DIR=""
  MCP_DIR=""
  LOG_DIR="${OPENCLAW_HOME}/logs"
else
  IN_CONTAINER=false
  COMPOSE_DIR="$OPENCLAW_COMPOSE_DIR"
  MCP_DIR="/root/.openclaw/mcp-servers/openclaw-gateway"
  LOG_DIR="/root/.openclaw/logs"
fi

# --- Helper: run openclaw commands in either context ---
oc_cmd() {
  if [ "$IN_CONTAINER" = true ]; then
    openclaw "$@" 2>/dev/null | grep -v "level=warning"
  else
    cd "$COMPOSE_DIR" && docker compose exec -T openclaw-gateway openclaw "$@" 2>/dev/null | grep -v "level=warning"
  fi
}

[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

# --- Dynamic agent list from openclaw.json ---
if [ "$IN_CONTAINER" = true ]; then
  AGENTS_JSON=$(python3 -c "import sys,json; print(' '.join(a['id'] for a in json.load(open('${OPENCLAW_HOME}/openclaw.json')).get('agents',{}).get('list',[])))" 2>/dev/null || echo "")
else
  AGENTS_JSON=$(cd "$COMPOSE_DIR" && docker compose exec -T openclaw-gateway cat /home/node/.openclaw/openclaw.json 2>/dev/null | python3 -c "import sys,json; print(' '.join(a['id'] for a in json.load(sys.stdin).get('agents',{}).get('list',[])))" 2>/dev/null || echo "")
fi
if [ -z "$AGENTS_JSON" ]; then
  AGENTS_JSON="relay main spec-projects spec-github spec-dev spec-reactor spec-browser spec-research spec-security spec-ops spec-design spec-systems spec-comms spec-strategy spec-quartermaster spec-historian spec-realist eoin"
fi
read -ra AGENTS <<< "$AGENTS_JSON"

# Log a load snapshot before any resets (feeds agent satisfaction data)
# Skipped in container context — agent-load-snapshot.sh may not be container-safe
mkdir -p "$LOG_DIR"
if [ "$IN_CONTAINER" = false ]; then
  /root/.openclaw/scripts/agent-load-snapshot.sh --json >> "$LOG_DIR/agent-load-history.jsonl" 2>/dev/null || true
fi

bloated_keys=()

for agent in "${AGENTS[@]}"; do
  json=$(oc_cmd sessions --agent "$agent" --json)
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
  oc_cmd sessions cleanup --all-agents --enforce --fix-missing 2>/dev/null | tail -3
  exit 0
fi

echo ""
echo "Found ${#bloated_keys[@]} session(s) over ${THRESHOLD}%"

if [ "$DRY_RUN" = true ]; then
  echo "(dry-run — no changes)"
  exit 0
fi

# Reset via gateway WS — requires host context (WS + node)
if [ "$IN_CONTAINER" = true ]; then
  echo "ERROR: Session reset requires host context (docker compose + WS). Run without --dry-run from host."
  exit 1
fi
GATEWAY_TOKEN=$(grep OPENCLAW_GATEWAY_TOKEN "$COMPOSE_DIR/.env" 2>/dev/null | cut -d= -f2)
export OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN"
cd "$MCP_DIR"
node session-bulk-reset.js "${bloated_keys[@]}" 2>&1

echo ""
# Also run built-in cleanup for orphaned entries
oc_cmd sessions cleanup --all-agents --enforce --fix-missing 2>/dev/null | tail -3
echo "Session maintenance complete."

# Log post-reset snapshot too (shows effect of maintenance)
/root/.openclaw/scripts/agent-load-snapshot.sh --json >> "$LOG_DIR/agent-load-history.jsonl" 2>/dev/null || true
