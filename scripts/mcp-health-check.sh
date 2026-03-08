#!/usr/bin/env bash
# mcp-health-check.sh — Check Gateway WebSocket + MCP server health
#
# Tests:
#   1. Gateway WebSocket reachable (ws://127.0.0.1:18789)
#   2. Gateway responds to health request
#   3. MCP server process exists (when run via Claude Code)
#
# Usage:
#   mcp-health-check.sh              # human-readable
#   mcp-health-check.sh --json       # machine-readable
#   mcp-health-check.sh --check      # exit 1 if unhealthy

set -eo pipefail

MODE="${1:-table}"
GATEWAY_URL="ws://127.0.0.1:18789"
GATEWAY_PORT=18789
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
COMPOSE_DIR="/root/openclaw"

status="HEALTHY"
checks=()

# Check 1: Gateway port listening
if ss -tlnp 2>/dev/null | grep -q ":${GATEWAY_PORT} " || netstat -tlnp 2>/dev/null | grep -q ":${GATEWAY_PORT} "; then
  checks+=('{"check":"gateway_port","status":"ok","detail":"Port 18789 listening"}')
else
  checks+=('{"check":"gateway_port","status":"fail","detail":"Port 18789 not listening"}')
  status="DOWN"
fi

# Check 2: Gateway container running
gw_state=$(cd "$COMPOSE_DIR" && docker compose ps openclaw-gateway --format json 2>/dev/null | jq -r '.State // .state // "unknown"' 2>/dev/null)
if [ "$gw_state" = "running" ]; then
  checks+=("{\"check\":\"container\",\"status\":\"ok\",\"detail\":\"Container state: $gw_state\"}")
else
  checks+=("{\"check\":\"container\",\"status\":\"fail\",\"detail\":\"Container state: $gw_state\"}")
  status="DOWN"
fi

# Check 3: Gateway health endpoint via CLI
health_out=$(cd "$COMPOSE_DIR" && docker compose exec -T openclaw-gateway openclaw health 2>&1 | grep -v "level=warning" | head -5)
if echo "$health_out" | grep -qi "ok\|healthy\|running\|ready"; then
  checks+=('{"check":"gateway_health","status":"ok","detail":"Gateway health: OK"}')
else
  checks+=("{\"check\":\"gateway_health\",\"status\":\"warn\",\"detail\":\"Gateway health: ${health_out:0:80}\"}")
  [ "$status" = "HEALTHY" ] && status="DEGRADED"
fi

# Check 4: WebSocket handshake test (lightweight — just check TCP connect)
if timeout 3 bash -c "echo > /dev/tcp/127.0.0.1/$GATEWAY_PORT" 2>/dev/null; then
  checks+=('{"check":"ws_connect","status":"ok","detail":"WebSocket TCP handshake OK"}')
else
  checks+=('{"check":"ws_connect","status":"fail","detail":"WebSocket TCP handshake failed"}')
  status="DOWN"
fi

# Check 5: Discord channel connected
discord_state=$(cd "$COMPOSE_DIR" && docker compose exec -T openclaw-gateway openclaw channels status 2>&1 | grep -v "level=warning" | grep -i "discord" | head -1)
if echo "$discord_state" | grep -qi "connected\|ok\|ready"; then
  checks+=('{"check":"discord","status":"ok","detail":"Discord connected"}')
elif [ -n "$discord_state" ]; then
  checks+=("{\"check\":\"discord\",\"status\":\"warn\",\"detail\":\"Discord: ${discord_state:0:80}\"}")
  [ "$status" = "HEALTHY" ] && status="DEGRADED"
else
  checks+=('{"check":"discord","status":"warn","detail":"Discord status unknown"}')
  [ "$status" = "HEALTHY" ] && status="DEGRADED"
fi

# Check 6: MCP server config exists
if [ -f /root/.claude/settings.json ] && grep -q "openclaw" /root/.claude/settings.json 2>/dev/null; then
  checks+=('{"check":"mcp_config","status":"ok","detail":"MCP server configured in Claude settings"}')
else
  checks+=('{"check":"mcp_config","status":"warn","detail":"MCP server not in Claude settings"}')
  [ "$status" = "HEALTHY" ] && status="DEGRADED"
fi

# Output
if [ "$MODE" = "--json" ]; then
  echo "{\"timestamp\":\"$TIMESTAMP\",\"status\":\"$status\",\"checks\":[$(IFS=,; echo "${checks[*]}")]}"
elif [ "$MODE" = "--check" ]; then
  if [ "$status" = "HEALTHY" ]; then
    echo "Gateway + MCP: HEALTHY (all checks passed)"
    exit 0
  else
    echo "Gateway + MCP: $status"
    for c in "${checks[@]}"; do
      s=$(echo "$c" | jq -r '.status')
      [ "$s" != "ok" ] && echo "  $(echo "$c" | jq -r '"\(.check): \(.detail)"')"
    done
    exit 1
  fi
else
  printf "%-20s %-8s %s\n" "CHECK" "STATUS" "DETAIL"
  printf "%-20s %-8s %s\n" "-----" "------" "------"
  for c in "${checks[@]}"; do
    check=$(echo "$c" | jq -r '.check')
    s=$(echo "$c" | jq -r '.status')
    detail=$(echo "$c" | jq -r '.detail')
    printf "%-20s %-8s %s\n" "$check" "$s" "$detail"
  done
  echo ""
  echo "Overall: $status ($TIMESTAMP)"
fi

# Auto-log failures to issue tracker
if [ "$status" != "HEALTHY" ]; then
  for c in "${checks[@]}"; do
    s=$(echo "$c" | jq -r '.status')
    if [ "$s" != "ok" ]; then
      detail=$(echo "$c" | jq -r '"\(.check): \(.detail)"')
      issue-log "MCP health: $detail" --source mcp-health-check --severity high 2>/dev/null || true
    fi
  done
fi
