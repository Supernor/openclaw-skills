#!/usr/bin/env bash
# codex-reauth-telegram.sh — FULL REAUTH: device auth flow + Telegram notification + gateway sync.
#
# NOTE FOR AGENTS: Unless you specifically need the full reauth flow, start with
# fix-codex-auth.sh instead — it checks if host tokens are still valid first
# (fast 30s sync) and only falls through to this script if they're actually expired.
#
#   fix-codex-auth.sh             <- START HERE (auto-detects and picks the right path)
#   codex-reauth-telegram.sh      <- you are here (full reauth, sends link to Robert)
#   sync-codex-auth.sh            <- sync-only (host tokens already valid)
#
# Role: Relay or Eoin sends /reauth -> this script runs, sends device auth URL to Telegram,
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
# 900s not 120s: the login process must stay alive polling until the user finishes on their
# phone — killing it invalidates the code server-side ("couldn't authorize this device").
# 900s matches the code's own 15-minute expiry.
timeout 900 codex login --device-auth > "$TEMP" 2>&1 &
AUTH_PID=$!

# Wait for URL to appear in output (up to 15 seconds)
URL=""
CODE=""
for i in $(seq 1 30); do
    sleep 0.5
    if [ -f "$TEMP" ]; then
        # Codex CLI >=0.144 prints the code on its OWN line under "Enter this one-time code";
        # old "code: XXXX" same-line format kept as fallback. ANSI codes stripped first.
        # || true on every capture: under set -e, a no-match grep exit(1) inside $() KILLS the
        # script silently — this was the original silent-death bug, not just the regex.
        CLEAN=$(sed 's/\x1b\[[0-9;]*m//g' "$TEMP" || true)
        URL=$(echo "$CLEAN" | grep -oP 'https://[^\s]+' | head -1 || true)
        CODE=$(echo "$CLEAN" | grep -oP '^\s*[A-Z0-9]{4,6}-[A-Z0-9]{4,6}\s*$' | tr -d '[:space:]' | head -1 || true)
        if [ -z "$CODE" ]; then
            CODE=$(echo "$CLEAN" | grep -oP 'code[:\s]+([A-Z0-9-]+)' | head -1 | grep -oP '[A-Z0-9-]+$' || true)
        fi
        if [ -n "$URL" ]; then
            break
        fi
    fi
done

if [ -z "$URL" ]; then
    LOGIN_ERR=$(tail -3 "$TEMP" 2>/dev/null | tr '\n' ' ' || true)
    log "ERROR: Could not extract auth URL. codex login said: ${LOGIN_ERR:-<no output>}"
    send_notification "Codex reauth failed — couldn't get auth URL. codex login said: ${LOGIN_ERR:-<no output>}. (429 = rate-limited, wait ~15 min. Otherwise try manually: \`codex login\`)"
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

    # Step 5: Sync to gateway — full wiring per scar gateway-auth-wrong-door-20260720:
    # (a) gpt-5.5 runs via the codex-app-server plugin; per-agent codex-home/auth.json must match.
    # (b) paste into BOTH openai profiles (auth.order tries pool-b first).
    # (c) the runtime only loads auth profiles at BOOT — restart is REQUIRED, paste alone does nothing.
    log "Distributing auth.json to agent codex-homes..."
    for agent in relay eoin main; do
        AH="/root/.openclaw/agents/$agent/agent/codex-home/auth.json"
        cp /root/.codex/auth.json "$AH" && chown 1000:1000 "$AH" && chmod 600 "$AH" \
            && log "  codex-home synced: $agent" || log "  codex-home sync FAILED: $agent"
    done
    log "Pasting token into gateway auth profiles (default + pool-b)..."
    env OPENAI_SYNC_NO_RESTART=1 /root/.openclaw/scripts/sync-openai-token.sh >/dev/null 2>&1 || true
    env OPENAI_SYNC_NO_RESTART=1 OPENAI_SYNC_HOST_AUTH=/root/.codex/auth.json OPENAI_SYNC_PROFILE=openai:pool-b \
        /root/.openclaw/scripts/sync-openai-token.sh >/dev/null 2>&1 || true
    /root/.openclaw/scripts/sync-codex-auth.sh 2>/dev/null || true
    log "Restarting gateway (auth profiles load at boot only)..."
    docker compose -f /root/openclaw/docker-compose.yml restart openclaw-gateway >/dev/null 2>&1 \
        && log "Gateway restarted" || log "Gateway restart FAILED — check docker"

    send_notification "Codex reauth complete. Tokens synced to host + 3 agent codex-homes + both gateway profiles; gateway restarted. Verify: ask Relay which model it is on."
    log "Reauth flow complete"
    exit 0
else
    log "Device auth failed (exit $AUTH_EXIT)"
    send_notification "Codex reauth failed (exit ${AUTH_EXIT}). Try manually: \`codex login\`"
    exit 1
fi
