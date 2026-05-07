#!/bin/bash
# mcp-probe — Tests MCP endpoint health from host side
#
# Usage:
#   mcp-probe.sh              # Test all endpoints
#   mcp-probe.sh <endpoint>   # Test specific endpoint

set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "mcp-probe — Tests MCP endpoint health from host side"
    echo ""
    echo "Usage: mcp-probe.sh"
    echo ""
    echo "Tests: gateway (18789), provider-health (18791), bridge (8083), docker, SQLite"
    echo ""
    echo "Exit codes:"
    echo "  0 = all endpoints responding"
    echo "  N = number of DOWN or WARN endpoints"
    echo ""
    echo "OUTPUT KEY:"
    echo "  UP:   = endpoint responding with valid data"
    echo "  DOWN: = endpoint unreachable (timeout, refused, no response)"
    echo "  WARN: = endpoint responded but with unexpected status/format"
    echo ""
    echo "KNOWN ISSUES:"
    echo "  - provider-health (18791) and fleet-status (18791) are currently DOWN"
    echo "    These are gateway internal endpoints, not Bridge endpoints."
    echo "    Chart: issue-engine-usage-poisoned-data-20260506"
    exit 0
fi

GATEWAY_PORT=18789
PROVIDER_PORT=18791
BRIDGE_PORT=8083
ERRORS=0

probe() {
    local name="$1" url="$2" timeout="${3:-5}"
    start=$(date +%s%N)
    result=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url" 2>/dev/null) || result="000"
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))

    if [ "$result" = "200" ]; then
        echo "UP:   $name (${ms}ms, HTTP $result)"
    elif [ "$result" = "000" ]; then
        echo "DOWN: $name (timeout/refused)"
        ERRORS=$((ERRORS + 1))
    else
        echo "WARN: $name (${ms}ms, HTTP $result)"
        ERRORS=$((ERRORS + 1))
    fi
}

probe_json() {
    local name="$1" url="$2" timeout="${3:-5}"
    start=$(date +%s%N)
    body=$(curl -s --max-time "$timeout" "$url" 2>/dev/null) || body=""
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))

    if [ -z "$body" ]; then
        echo "DOWN: $name (no response)"
        ERRORS=$((ERRORS + 1))
    elif echo "$body" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        echo "UP:   $name (${ms}ms, valid JSON)"
    else
        echo "WARN: $name (${ms}ms, non-JSON response)"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== MCP Endpoint Probe ==="
echo "Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

echo "--- Gateway (port $GATEWAY_PORT) ---"
probe "gateway-health" "http://localhost:${GATEWAY_PORT}/healthz"

echo ""
echo "--- Provider Health (port $PROVIDER_PORT) ---"
probe_json "provider-health" "http://localhost:${PROVIDER_PORT}/v1/provider-health"
probe_json "fleet-status" "http://localhost:${PROVIDER_PORT}/v1/fleet"

echo ""
echo "--- Bridge (port $BRIDGE_PORT) ---"
probe_json "bridge-health" "http://localhost:${BRIDGE_PORT}/api/health"
probe_json "bridge-auth" "http://localhost:${BRIDGE_PORT}/api/auth/status"
probe_json "bridge-tasks" "http://localhost:${BRIDGE_PORT}/api/tasks?limit=1"
probe_json "bridge-intents" "http://localhost:${BRIDGE_PORT}/api/intents"

echo ""
echo "--- Docker ---"
if docker compose ps 2>/dev/null | grep -q "healthy"; then
    echo "UP:   gateway container (healthy)"
else
    echo "WARN: gateway container (not healthy or not running)"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "--- SQLite ---"
if sqlite3 /root/.openclaw/ops.db "SELECT 1;" >/dev/null 2>&1; then
    mode=$(sqlite3 /root/.openclaw/ops.db "PRAGMA journal_mode;" 2>/dev/null)
    echo "UP:   ops.db (journal_mode=$mode)"
else
    echo "DOWN: ops.db (unreadable)"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== Result: $ERRORS issues ==="
exit $ERRORS
