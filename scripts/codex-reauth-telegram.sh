#!/usr/bin/env bash
# Alignment: one-tap Codex OAuth reauth triggered from Telegram.
# Role: Relay or Eoin sends /reauth → this script runs, sends device auth URL to Telegram,
# user taps the link on their phone, auth completes, gateway synced.
# Dependencies: codex CLI, sync-codex-auth.sh, Telegram bot token.
# Usage: codex-reauth-telegram.sh [chat_id]
# Reference: chart policy-auto-correction-recursion-guard

set -eo pipefail

CHAT_ID="${1:-8561305605}"
LOG="/root/.openclaw/logs/codex-reauth.log"
source /root/openclaw/.env 2>/dev/null || true
OPS_CODEX_WEBHOOK=$(cat /root/.openclaw/ops-codex-webhook-url.txt 2>/dev/null)

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$LOG"; }

# Route to Discord ops-codex (domain-routed: Codex auth → ops-codex channel)
send_notification() {
    local msg="$1"
    if [ -n "$OPS_CODEX_WEBHOOK" ]; then
        curl -sf -X POST "$OPS_CODEX_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"${msg}\"}" \
            > /dev/null 2>&1 || true
    fi
}

# Telegram DM only for auth links that need human action
send_telegram_auth_link() {
    local msg="$1"
    local token="${TELEGRAM_BOT_TOKEN_ROBERT:-$TAP_BOT_TOKEN}"
    curl -sf -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\": \"${CHAT_ID}\", \"text\": \"${msg}\", \"parse_mode\": \"Markdown\"}" \
        > /dev/null 2>&1 || true
}

# Step 1: Check BOTH Codex pools
log "Checking Codex pool status..."

POOL_A_OK=false
POOL_B_OK=false

# Test pool A (default ~/.codex)
if cd /root/openclaw && timeout 10 codex exec --skip-git-repo-check "echo ok" >/dev/null 2>&1; then
    POOL_A_OK=true
    log "Pool A: VALID"
else
    log "Pool A: EXPIRED or failing"
fi

# Test pool B (separate home dir)
if [ -d /root/.codex-pool-b ]; then
    if HOME=/root/.codex-pool-b cd /root/openclaw && timeout 10 HOME=/root/.codex-pool-b codex exec --skip-git-repo-check "echo ok" >/dev/null 2>&1; then
        POOL_B_OK=true
        log "Pool B: VALID"
    else
        log "Pool B: EXPIRED or failing"
    fi
else
    log "Pool B: not configured (no /root/.codex-pool-b)"
fi

if [ "$POOL_A_OK" = true ] && [ "$POOL_B_OK" = true ]; then
    log "Both pools are VALID — no reauth needed"
    send_notification "Both Codex pools are working. No reauth needed.
Pool A: OK
Pool B: OK"
    /root/.openclaw/scripts/sync-codex-auth.sh 2>/dev/null || true
    exit 0
fi

# Report which pools need attention
STATUS_MSG="Codex pool status:
Pool A: $([ "$POOL_A_OK" = true ] && echo 'OK' || echo 'NEEDS REAUTH')
Pool B: $([ "$POOL_B_OK" = true ] && echo 'OK' || echo 'NEEDS REAUTH')"
send_notification "$STATUS_MSG"

# Step 2: Auth is expired — start device auth flow
log "Codex auth EXPIRED — starting device auth flow"
send_notification "Codex auth expired. Starting reauth — watch for the link..."

# Run device auth and capture output
TEMP=$(mktemp)
timeout 120 codex login --device-auth > "$TEMP" 2>&1 &
AUTH_PID=$!

# Wait for URL to appear in output (up to 15 seconds)
URL=""
CODE=""
for i in $(seq 1 30); do
    sleep 0.5
    if [ -f "$TEMP" ]; then
        URL=$(grep -oP 'https://[^\s]+' "$TEMP" | head -1)
        CODE=$(grep -oP 'code[:\s]+([A-Z0-9-]+)' "$TEMP" | head -1 | grep -oP '[A-Z0-9-]+$')
        if [ -n "$URL" ]; then
            break
        fi
    fi
done

if [ -z "$URL" ]; then
    log "ERROR: Could not extract auth URL from codex login output"
    send_notification "Codex reauth failed — couldn't get auth URL. Try manually: \`codex login\`"
    kill $AUTH_PID 2>/dev/null
    rm -f "$TEMP"
    exit 1
fi

# Step 3: Send the URL to Telegram — one tap to auth
log "Device auth URL: $URL"
MSG="*Codex Reauth Required*

Tap this link to authorize:
${URL}"

if [ -n "$CODE" ]; then
    MSG="${MSG}

Code: \`${CODE}\`"
fi

MSG="${MSG}

After you authorize, I will sync the tokens and restart the gateway automatically."

send_telegram_auth_link "$MSG"

# Step 4: Wait for auth to complete (codex login will exit when done)
log "Waiting for user to complete auth..."
wait $AUTH_PID
AUTH_EXIT=$?
rm -f "$TEMP"

if [ $AUTH_EXIT -eq 0 ]; then
    log "Device auth completed successfully"

    # Step 5: Sync to gateway
    log "Syncing tokens to gateway..."
    /root/.openclaw/scripts/sync-codex-auth.sh 2>/dev/null || true

    send_notification "Codex reauth complete. Tokens synced. Gateway restarted. You are good to go."
    log "Reauth flow complete"
    exit 0
else
    log "Device auth failed (exit $AUTH_EXIT)"
    send_notification "Codex reauth failed (exit ${AUTH_EXIT}). Try manually: \`codex login\`"
    exit 1
fi
