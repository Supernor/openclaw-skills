#!/usr/bin/env bash
# Alignment: safe gateway restart with user notification and health verification.
# Role: notify user BEFORE restart (via direct Telegram, bypasses gateway),
# restart gateway, poll for health, notify user AFTER.
# Dependencies: TAP_BOT_TOKEN, docker compose, curl.
# Key patterns: Telegram notification bypasses the gateway (direct API call)
# so it works even when gateway is down. Host-side only.
# Reference: chart policy-codex-self-healing (alert delivery never depends on thing being monitored)

set -eo pipefail

CHAT_ID="${1:-8561305605}"
REASON="${2:-System update}"
FORCE=false
# Parse --force flag from any position
for arg in "$@"; do
    [ "$arg" = "--force" ] && FORCE=true
done
source /root/openclaw/.env 2>/dev/null || true
# Discord ops-gateway for restart notifications (domain-routed)
OPS_WEBHOOK=$(cat /root/.openclaw/ops-gateway-webhook-url.txt 2>/dev/null)
COMPOSE="/root/openclaw/docker-compose.yml"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1"; }

# Direct Telegram — bypasses gateway (works when gateway is the thing restarting)
telegram_direct() {
    local msg="$1"
    local token="${TELEGRAM_BOT_TOKEN_ROBERT:-}"
    [ -z "$token" ] && return 1
    curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${msg}" \
        -d parse_mode=Markdown >/dev/null 2>&1 || true
}

# Discord ops-gateway channel — domain-routed notifications
# Uses webhook (works even when gateway is down — direct Discord API)
notify() {
    local msg="$1"
    telegram_direct "$msg"
    if [ -n "$OPS_WEBHOOK" ]; then
        curl -sf -X POST "$OPS_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"${msg}\"}" \
            > /dev/null 2>&1 || true
    fi
}

# Step 0: Check for active sessions and in-progress tasks before restarting
# A restart kills all active gateway sessions — lost messages, dropped conversations.
# Lesson learned 2026-05-22: Robert lost a Telegram message because restart happened
# while getUpdates had already acknowledged it.
BUSY_ITEMS=""

# Check gateway sessions active in last 5 minutes
# Capture output first to avoid pipefail issues with grep
SESSION_OUTPUT=$(timeout 15 docker compose -f "$COMPOSE" exec -T openclaw-gateway \
    openclaw sessions --active 5 --all-agents 2>&1) || true
ACTIVE_SESSIONS=$(echo "$SESSION_OUTPUT" | grep -oP 'Sessions listed: \K\d+' 2>/dev/null) || ACTIVE_SESSIONS="0"
if [ "$ACTIVE_SESSIONS" -gt 0 ]; then
    # Extract agent names + age for the busy message (format: "relay 2m ago, relay 4m ago")
    SESSION_DETAIL=$(echo "$SESSION_OUTPUT" | awk '/^ *(relay|main|spec-|eoin)/ {printf "%s %s %s, ", $1, $4, $5}' | sed 's/, $//')
    BUSY_ITEMS="${BUSY_ITEMS}${ACTIVE_SESSIONS} active session(s): ${SESSION_DETAIL:-unknown}. "
fi

# Check in-progress tasks in ops.db
IN_PROGRESS=$(sqlite3 /root/.openclaw/ops.db \
    "SELECT COUNT(*) FROM tasks WHERE status='in_progress'" 2>/dev/null) || IN_PROGRESS="0"
if [ "$IN_PROGRESS" -gt 0 ]; then
    TASK_DETAIL=$(sqlite3 /root/.openclaw/ops.db \
        "SELECT 'Task #' || id || ': ' || substr(task,1,50) FROM tasks WHERE status='in_progress' LIMIT 3" \
        2>/dev/null | tr '\n' '; ')
    BUSY_ITEMS="${BUSY_ITEMS}${IN_PROGRESS} in-progress task(s): ${TASK_DETAIL}"
fi

if [ -n "$BUSY_ITEMS" ] && [ "$FORCE" = false ]; then
    log "BLOCKED: Restart would interrupt active work: ${BUSY_ITEMS}"
    echo "BUSY: Restart would kill: ${BUSY_ITEMS}"
    echo "Use --force to restart anyway, or wait for work to complete."
    exit 2  # Exit 2 = blocked by busy check (distinct from 1 = restart failed)
fi

if [ -n "$BUSY_ITEMS" ] && [ "$FORCE" = true ]; then
    log "WARNING: Force restart despite active work: ${BUSY_ITEMS}"
fi

# Step 1: Notify user BEFORE restart
log "Notifying user of pending restart"
notify "🔄 Gateway restarting. Reason: ${REASON}. ~30 seconds downtime."

# Step 2: Restart gateway
log "Restarting gateway..."
docker compose -f "$COMPOSE" restart openclaw-gateway 2>&1 || {
    notify "Gateway restart FAILED. Manual intervention may be needed."
    exit 1
}

# Step 3: Poll for health (up to 60 seconds)
log "Waiting for gateway to come up..."
HEALTHY=false
for i in $(seq 1 12); do
    sleep 5
    # Check container is running
    STATUS=$(docker compose -f "$COMPOSE" ps --format json openclaw-gateway 2>/dev/null | python3 -c "import json,sys;d=json.loads(sys.stdin.read());print(d.get('State','unknown'))" 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "running" ]; then
        # Try a health check inside container
        if docker compose -f "$COMPOSE" exec -T openclaw-gateway openclaw health > /dev/null 2>&1; then
            HEALTHY=true
            log "Gateway healthy after ${i}x5 = $((i*5)) seconds"
            break
        fi
    fi
    log "Waiting... (attempt $i/12, status=$STATUS)"
done

# Step 4: Notify user AFTER
if [ "$HEALTHY" = true ]; then
    notify "✅ Gateway back online. Healthy."
    log "Restart complete — gateway healthy"
    exit 0
else
    notify "⚠️ Gateway restarted but health check failed after 60s. Monitoring continues."
    log "WARNING: Gateway may not be fully healthy"
    exit 1
fi
