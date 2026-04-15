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
source /root/openclaw/.env 2>/dev/null || true
# Discord ops-gateway for restart notifications (domain-routed)
OPS_WEBHOOK=$(cat /root/.openclaw/ops-gateway-webhook-url.txt 2>/dev/null)
COMPOSE="/root/openclaw/docker-compose.yml"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1"; }

# Discord ops-gateway channel — domain-routed notifications
# Uses webhook (works even when gateway is down — direct Discord API)
notify() {
    local msg="$1"
    if [ -n "$OPS_WEBHOOK" ]; then
        curl -sf -X POST "$OPS_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"${msg}\"}" \
            > /dev/null 2>&1 || true
    fi
}

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
