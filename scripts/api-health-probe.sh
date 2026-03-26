#!/usr/bin/env bash
# api-health-probe.sh — Zero-cost probes for external APIs and critical services.
# State-change driven: only alerts when status CHANGES, not on every failure.
# Writes to health_snapshots table so Bridge can render live status.
# Intent: Observable [I13], Resilient [I08].

set -uo pipefail

OPS_DB="/root/.openclaw/ops.db"
ENV_FILE="/root/openclaw/.env"
STATE_FILE="/root/.openclaw/api-probe-state.json"
LOG="/root/.openclaw/logs/api-health-probe.log"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [probe] $1" >> "$LOG"; }

# Initialize state file if missing
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"
PREV_STATE=$(cat "$STATE_FILE" 2>/dev/null) || PREV_STATE='{}'

# Read token dynamically from .env (not hardcoded)
read_env_token() {
  local KEY="$1"
  grep "^${KEY}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d "'" | tr -d '"'
}

# Direct Telegram alert (same pattern as stability-monitor)
telegram_direct() {
  local MSG="$1"
  local TOKEN
  TOKEN=$(read_env_token "TELEGRAM_BOT_TOKEN_ROBERT")
  [ -z "$TOKEN" ] && TOKEN=$(read_env_token "TELEGRAM_BOT_TOKEN")
  [ -z "$TOKEN" ] && return 1
  local CHAT_ID
  CHAT_ID=$(telegram-resolve robert 2>/dev/null || echo "8561305605")
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" -d text="${MSG}" >/dev/null 2>&1
}

# Get previous status for a provider (state-change detection)
prev_status() {
  echo "$PREV_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$1','unknown'))" 2>/dev/null || echo "unknown"
}

RESULTS='{}'
CHANGES=""

# --- Probe: Gateway Container ---
GW_STATUS=$(docker inspect --format '{{.State.Status}}' openclaw-openclaw-gateway-1 2>/dev/null || echo "missing")
GW_HEALTHY=$( [ "$GW_STATUS" = "running" ] && echo "healthy" || echo "unhealthy" )
RESULTS=$(echo "$RESULTS" | python3 -c "import json,sys; d=json.load(sys.stdin); d['gateway']='$GW_HEALTHY'; json.dump(d,sys.stdout)")
if [ "$GW_HEALTHY" != "$(prev_status gateway)" ]; then
  CHANGES="${CHANGES}Gateway: $(prev_status gateway) -> $GW_HEALTHY. "
fi

# --- Probe: NIM API (Mistral) ---
NIM_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://integrate.api.nvidia.com/v1/models" 2>/dev/null || echo "000")
NIM_HEALTHY=$( [ "$NIM_CODE" = "200" ] && echo "healthy" || echo "unhealthy" )
RESULTS=$(echo "$RESULTS" | python3 -c "import json,sys; d=json.load(sys.stdin); d['nvidia']='$NIM_HEALTHY'; json.dump(d,sys.stdout)")
if [ "$NIM_HEALTHY" != "$(prev_status nvidia)" ]; then
  CHANGES="${CHANGES}NIM API: $(prev_status nvidia) -> $NIM_HEALTHY (HTTP $NIM_CODE). "
fi

# --- Probe: Telegram Bot ---
TG_TOKEN=$(read_env_token "TELEGRAM_BOT_TOKEN_ROBERT")
[ -z "$TG_TOKEN" ] && TG_TOKEN=$(read_env_token "TELEGRAM_BOT_TOKEN")
if [ -n "$TG_TOKEN" ]; then
  TG_RESP=$(curl -s --max-time 5 "https://api.telegram.org/bot${TG_TOKEN}/getMe" 2>/dev/null)
  TG_OK=$(echo "$TG_RESP" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('ok') else 'false')" 2>/dev/null || echo "false")
  TG_HEALTHY=$( [ "$TG_OK" = "true" ] && echo "healthy" || echo "unhealthy" )
else
  TG_HEALTHY="unknown"
fi
RESULTS=$(echo "$RESULTS" | python3 -c "import json,sys; d=json.load(sys.stdin); d['telegram-bot']='$TG_HEALTHY'; json.dump(d,sys.stdout)")
if [ "$TG_HEALTHY" != "$(prev_status telegram-bot)" ]; then
  CHANGES="${CHANGES}Telegram bot: $(prev_status telegram-bot) -> $TG_HEALTHY. "
fi

# --- Probe: Bridge API ---
BR_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:8083/api/health" 2>/dev/null || echo "000")
BR_HEALTHY=$( [ "$BR_CODE" = "200" ] && echo "healthy" || echo "unhealthy" )
RESULTS=$(echo "$RESULTS" | python3 -c "import json,sys; d=json.load(sys.stdin); d['bridge']='$BR_HEALTHY'; json.dump(d,sys.stdout)")
if [ "$BR_HEALTHY" != "$(prev_status bridge)" ]; then
  CHANGES="${CHANGES}Bridge: $(prev_status bridge) -> $BR_HEALTHY (HTTP $BR_CODE). "
fi

# --- Probe: Host-Ops Executor ---
EXEC_HEALTHY=$( pgrep -f "host-ops-executor.py" >/dev/null 2>&1 && echo "healthy" || echo "unhealthy" )
RESULTS=$(echo "$RESULTS" | python3 -c "import json,sys; d=json.load(sys.stdin); d['executor']='$EXEC_HEALTHY'; json.dump(d,sys.stdout)")
if [ "$EXEC_HEALTHY" != "$(prev_status executor)" ]; then
  CHANGES="${CHANGES}Executor: $(prev_status executor) -> $EXEC_HEALTHY. "
fi

# --- Probe: Relay Handoff Watcher ---
RELAY_HANDOFF_HEALTHY=$( pgrep -f "relay-handoff-watcher.py" >/dev/null 2>&1 && echo "healthy" || echo "unhealthy" )
RESULTS=$(echo "$RESULTS" | python3 -c "import json,sys; d=json.load(sys.stdin); d['relay-handoff-watcher']='$RELAY_HANDOFF_HEALTHY'; json.dump(d,sys.stdout)")
if [ "$RELAY_HANDOFF_HEALTHY" != "$(prev_status relay-handoff-watcher)" ]; then
  CHANGES="${CHANGES}Relay handoff watcher: $(prev_status relay-handoff-watcher) -> $RELAY_HANDOFF_HEALTHY. "
fi

# --- Probe: Backbone Listener ---
BACKBONE_HEALTHY=$( pgrep -f "backbone-listener.py" >/dev/null 2>&1 && echo "healthy" || echo "unhealthy" )
RESULTS=$(echo "$RESULTS" | python3 -c "import json,sys; d=json.load(sys.stdin); d['backbone-listener']='$BACKBONE_HEALTHY'; json.dump(d,sys.stdout)")
if [ "$BACKBONE_HEALTHY" != "$(prev_status backbone-listener)" ]; then
  CHANGES="${CHANGES}Backbone listener: $(prev_status backbone-listener) -> $BACKBONE_HEALTHY. "
fi

# --- Probe: Telegram Listener ---
TELEGRAM_LISTENER_HEALTHY=$( pgrep -f "telegram-listener.py" >/dev/null 2>&1 && echo "healthy" || echo "unhealthy" )
RESULTS=$(echo "$RESULTS" | python3 -c "import json,sys; d=json.load(sys.stdin); d['telegram-listener']='$TELEGRAM_LISTENER_HEALTHY'; json.dump(d,sys.stdout)")
if [ "$TELEGRAM_LISTENER_HEALTHY" != "$(prev_status telegram-listener)" ]; then
  CHANGES="${CHANGES}Telegram listener: $(prev_status telegram-listener) -> $TELEGRAM_LISTENER_HEALTHY. "
fi

# --- Probe: Codex OAuth (check via gateway container) ---
CODEX_HEALTHY="unknown"
GW_RUNNING=$(docker inspect --format '{{.State.Status}}' openclaw-openclaw-gateway-1 2>/dev/null || echo "missing")
if [ "$GW_RUNNING" = "running" ]; then
  # Check if Codex can actually reach OpenAI by looking for recent auth errors in logs
  CODEX_ERRORS=$(docker compose -f /root/openclaw/docker-compose.yml logs --since=30m openclaw-gateway 2>&1 | grep -ci "openai-codex.*401\|token refresh failed\|oauth.*unauthorized" || true)
  CODEX_HEALTHY=$( [ "$CODEX_ERRORS" -eq 0 ] && echo "healthy" || echo "unhealthy" )
fi
RESULTS=$(echo "$RESULTS" | python3 -c "import json,sys; d=json.load(sys.stdin); d['codex-oauth']='$CODEX_HEALTHY'; json.dump(d,sys.stdout)")
if [ "$CODEX_HEALTHY" != "$(prev_status codex-oauth)" ] && [ "$CODEX_HEALTHY" != "unknown" ]; then
  CHANGES="${CHANGES}Codex OAuth: $(prev_status codex-oauth) -> $CODEX_HEALTHY. "
fi

# --- Write results to health_snapshots (Bridge reads this) ---
python3 -c "
import sqlite3, json, sys
ts = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
results = json.loads('''$RESULTS''')
conn = sqlite3.connect('$OPS_DB')
for provider, status in results.items():
    db_status = {
        'healthy': 'healthy',
        'unhealthy': 'quarantined',
        'unknown': 'disabled',
    }.get(status, 'disabled')
    reason = 'none' if status == 'healthy' else f'{provider} probe failed ({status})'
    conn.execute(
        'INSERT INTO health_snapshots (ts, provider, status, reason, failure_count, error_count, last_used, meta) '
        'VALUES (?, ?, ?, ?, 0, 0, ?, ?)',
        (ts, provider, db_status, reason, ts, json.dumps({'observed_status': status}))
    )
conn.commit()
conn.close()
" 2>/dev/null

# --- Save state for next run (state-change detection) ---
echo "$RESULTS" > "$STATE_FILE"

# --- Alert on state changes only (not every failure) ---
if [ -n "$CHANGES" ]; then
  log "STATE CHANGE: $CHANGES"
  telegram_direct "Probe: $CHANGES"
else
  log "OK: no state changes"
fi
