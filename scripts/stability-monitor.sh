#!/bin/bash
# Stability Monitor — runs every 5 minutes, alerts Robert on Telegram ONLY when something is wrong
# Designed to be quiet when healthy, loud when broken.
# State file tracks last-known state to avoid spam.
# Exit codes: 0=healthy, 1=monitored systems have problems, 2=monitoring itself is broken

set -uo pipefail

STATE_FILE="/root/.openclaw/stability-state.json"
LOG="/root/.openclaw/logs/stability-monitor.log"
TELEGRAM_TARGET=$(telegram-resolve robert)
CONTAINER="openclaw-openclaw-gateway-1"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >> "$LOG"; }

CHECK_ERRORS=0

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
  echo '{"gateway":"unknown","telegram":"unknown","discord":"unknown","rate_limited":false,"last_alert":"","consecutive_failures":0}' > "$STATE_FILE"
fi

PREV_STATE=$(cat "$STATE_FILE") || { log "CHECK FAILED: read state file"; CHECK_ERRORS=$((CHECK_ERRORS+1)); PREV_STATE='{}'; }
ALERTS=""
RECOVERED=""

# Check 1: Is the gateway container running?
CONTAINER_STATUS=$(docker inspect --format '{{.State.Status}}' "$CONTAINER" 2>/dev/null) || { log "CHECK FAILED: docker inspect"; CHECK_ERRORS=$((CHECK_ERRORS+1)); CONTAINER_STATUS="missing"; }
if [ "$CONTAINER_STATUS" != "running" ]; then
  ALERTS="${ALERTS}Gateway container is ${CONTAINER_STATUS}. "
  log "ALERT: Gateway $CONTAINER_STATUS"
fi

# Check 2: Is the gateway healthy? (only if container is running)
if [ "$CONTAINER_STATUS" = "running" ]; then
  HEALTH=$(docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw health 2>/dev/null | grep -v "level=warning") || { log "CHECK FAILED: openclaw health"; CHECK_ERRORS=$((CHECK_ERRORS+1)); HEALTH="HEALTH_CHECK_FAILED"; }

  # Telegram bot status
  if echo "$HEALTH" | grep -q "Telegram: ok"; then
    if echo "$PREV_STATE" | python3 -c "import json,sys; s=json.load(sys.stdin); exit(0 if s.get('telegram')=='down' else 1)" 2>/dev/null; then
      RECOVERED="${RECOVERED}Telegram bot recovered. "
    fi
  else
    ALERTS="${ALERTS}Telegram bot is DOWN. "
    log "ALERT: Telegram down"
  fi

  # Discord bot status
  if echo "$HEALTH" | grep -q "Discord: ok"; then
    if echo "$PREV_STATE" | python3 -c "import json,sys; s=json.load(sys.stdin); exit(0 if s.get('discord')=='down' else 1)" 2>/dev/null; then
      RECOVERED="${RECOVERED}Discord bot recovered. "
    fi
  else
    ALERTS="${ALERTS}Discord bot is DOWN. "
    log "ALERT: Discord down"
  fi

  # Check 3: Rate limit storm detection (>10 errors in last 5 min)
  ERROR_COUNT=$(docker compose -f /root/openclaw/docker-compose.yml logs --since=5m openclaw-gateway 2>&1 | grep -c "rate limit reached") || ERROR_COUNT=0
  if [ "$ERROR_COUNT" -gt 10 ]; then
    ALERTS="${ALERTS}Rate limit storm: ${ERROR_COUNT} rate-limit errors in 5 min. "
    log "ALERT: Rate limit storm ($ERROR_COUNT errors)"
  fi

  # Check 4: Crash loop detection
  RESTART_COUNT=$(docker inspect --format '{{.RestartCount}}' "$CONTAINER" 2>/dev/null) || { log "CHECK FAILED: docker restart count"; CHECK_ERRORS=$((CHECK_ERRORS+1)); RESTART_COUNT=0; }
  if [ "$RESTART_COUNT" -gt 3 ]; then
    ALERTS="${ALERTS}Gateway in restart loop (${RESTART_COUNT} restarts). "
    log "ALERT: Restart loop ($RESTART_COUNT)"
  fi
fi

# Check 5: Ollama (embedding service)
if ! curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
  ALERTS="${ALERTS}Ollama is DOWN (embeddings broken). "
  log "ALERT: Ollama down"
fi

# Check 7: Helm server crash detection
HELM_RESTARTS=$(systemctl show helm-server -p NRestarts --value 2>/dev/null) || { log "CHECK FAILED: systemctl helm"; CHECK_ERRORS=$((CHECK_ERRORS+1)); HELM_RESTARTS=0; }
PREV_HELM_RESTARTS=$(echo "$PREV_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('helm_restarts',0))" 2>/dev/null) || PREV_HELM_RESTARTS=0
if [ "$HELM_RESTARTS" -gt "$PREV_HELM_RESTARTS" ] 2>/dev/null; then
  NEW_CRASHES=$((HELM_RESTARTS - PREV_HELM_RESTARTS))
  ALERTS="${ALERTS}Helm server crashed ${NEW_CRASHES}x (total restarts: ${HELM_RESTARTS}). "
  log "ALERT: Helm crashed ${NEW_CRASHES}x (restarts: ${HELM_RESTARTS})"
fi

# Check 6: Disk space
DISK_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%') || { log "CHECK FAILED: df"; CHECK_ERRORS=$((CHECK_ERRORS+1)); DISK_PCT=0; }
if [ "$DISK_PCT" -gt 90 ]; then
  ALERTS="${ALERTS}Disk ${DISK_PCT}% full. "
  log "ALERT: Disk $DISK_PCT%"
fi

# Update state
TELEGRAM_STATE="up"
DISCORD_STATE="up"
RATE_LIMITED="false"
FAILURES=$(echo "$PREV_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('consecutive_failures',0))" 2>/dev/null) || FAILURES=0

if echo "$ALERTS" | grep -q "Telegram"; then TELEGRAM_STATE="down"; fi
if echo "$ALERTS" | grep -q "Discord"; then DISCORD_STATE="down"; fi
if echo "$ALERTS" | grep -q "Rate limit"; then RATE_LIMITED="true"; fi

if [ -n "$ALERTS" ]; then
  FAILURES=$((FAILURES + 1))
else
  FAILURES=0
fi

python3 -c "
import json
state = {
    'gateway': '$CONTAINER_STATUS',
    'telegram': '$TELEGRAM_STATE',
    'discord': '$DISCORD_STATE',
    'rate_limited': True if '$RATE_LIMITED' == 'true' else False,
    'last_check': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    'consecutive_failures': $FAILURES,
    'helm_restarts': int('$HELM_RESTARTS') if '$HELM_RESTARTS'.isdigit() else 0
}
if '$ALERTS':
    state['last_alert'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
    state['last_alert_text'] = '''$ALERTS'''
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
"

# Send alerts (only if container is running for Telegram delivery)
if [ -n "$ALERTS" ] && [ "$CONTAINER_STATUS" = "running" ]; then
  MSG="⚠️ System Alert

${ALERTS}
Consecutive failures: ${FAILURES}

Checked: $(date -u +%H:%M) UTC"

  docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway \
    openclaw message send --channel telegram --account robert --target "$TELEGRAM_TARGET" \
    -m "$MSG" 2>/dev/null | grep -v "level=warning" | tail -1
  log "Alert sent to Telegram"
fi

# Send recovery notices
if [ -n "$RECOVERED" ] && [ "$CONTAINER_STATUS" = "running" ]; then
  MSG="✅ Recovery: ${RECOVERED}

Checked: $(date -u +%H:%M) UTC"

  docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway \
    openclaw message send --channel telegram --account robert --target "$TELEGRAM_TARGET" \
    -m "$MSG" 2>/dev/null | grep -v "level=warning" | tail -1
  log "Recovery notice sent"
fi

# Quiet when healthy
if [ -z "$ALERTS" ] && [ -z "$RECOVERED" ]; then
  log "OK: All systems healthy"
fi

# Exit codes: 2=monitoring broken, 1=alerts found, 0=all healthy
[ "$CHECK_ERRORS" -gt 0 ] && exit 2
[ -n "$ALERTS" ] && exit 1
exit 0
