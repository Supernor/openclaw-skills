#!/usr/bin/env bash
# sync-openai-token.sh — keep the gateway's openai/gpt-5.5 auth fresh from the valid host Codex token.
#
# WHY THIS EXISTS (2026-06-29): OpenClaw 2026.6.10 migrated agent auth from auth-profiles.json into a
# per-agent SQLite store, which silently broke the old sync-codex-auth.sh (it wrote the now-dead
# auth-profiles.json path). The gateway's openai OAuth tokens then expired and Relay/Eoin fell back to
# nemotron while the Bridge still showed "pools healthy" (manual-1782765015). The SANCTIONED modern path
# (per `openclaw models auth login` itself) is `openclaw models auth paste-token` — it writes the current
# store wherever it lives now, no hardcoded path. paste-token stores an ACCESS token (no refresh), so this
# runs on a schedule to re-paste the host's always-fresh token before the ~7-day access token expires.
# No gateway restart needed — agents pick up the new token on next dispatch (verified 2026-06-29).
#
# Host token stays fresh because the Codex CLI auto-refreshes ~/.codex on use. If the HOST token is ALSO
# expired, this cannot fix it (a real OAuth re-auth needs Robert's browser: device-code) — it alerts instead.
set -uo pipefail

COMPOSE="docker compose -f /root/openclaw/docker-compose.yml"
HOST_AUTH="${OPENAI_SYNC_HOST_AUTH:-$HOME/.codex/auth.json}"
AGENTS="${OPENAI_SYNC_AGENTS:-relay eoin main}"
PROFILE="${OPENAI_SYNC_PROFILE:-openai:default}"
LOG="/root/.openclaw/logs/sync-openai-token.log"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$LOG"; }

# Extract the host access token + remaining hours from the JWT exp; empty token => not valid.
read -r TOKEN HOURS < <(python3 -c "
import json, base64, time, sys
try:
    a=json.load(open('$HOST_AUTH')); t=a.get('tokens',a); tok=t.get('access_token','')
    if not tok or '.' not in tok: print('', 0); sys.exit()
    p=tok.split('.')[1]; p+='='*(4-len(p)%4)
    exp=json.loads(base64.urlsafe_b64decode(p)).get('exp',0)
    rem=int((exp-time.time())/3600)
    print(tok if rem>0 else '', max(0,rem))
except Exception:
    print('', 0)
" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    log "HOST TOKEN EXPIRED/MISSING ($HOST_AUTH) — cannot sync. Needs a device-code re-auth (Robert)."
    echo "RESULT_LABEL: needs_reauth"   # cron-wrapper surfaces this on the Bridge cron-health view
    # Gateway-independent Telegram alert (don't depend on the thing that's down) — mirrors
    # stability-monitor.sh telegram_direct(): token from .env, chat id via telegram-resolve.
    TG=$(grep '^TELEGRAM_BOT_TOKEN_ROBERT=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
    [ -z "$TG" ] && TG=$(grep '^TELEGRAM_BOT_TOKEN=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
    CHAT=$(telegram-resolve robert 2>/dev/null)
    [ -n "$TG" ] && [ -n "$CHAT" ] && curl -s -X POST "https://api.telegram.org/bot${TG}/sendMessage" \
        -d chat_id="$CHAT" \
        -d text="⚠️ openai/gpt-5.5 auth: host Codex token expired — needs a browser re-auth (openclaw models auth login --provider openai --device-code). Agents on nemotron fallback until then." \
        >/dev/null 2>&1 || true
    exit 1
fi

log "Host token valid (${HOURS}h left). Pasting $PROFILE for: $AGENTS"
ok=0; fail=0
for agent in $AGENTS; do
    if echo "$TOKEN" | timeout 60 $COMPOSE exec -T openclaw-gateway \
         openclaw models auth --agent "$agent" paste-token --provider openai \
         --profile-id "$PROFILE" --expires-in "${HOURS}h" >/dev/null 2>&1; then
        log "  ✓ $agent"; ok=$((ok+1))
    else
        log "  ✗ $agent (paste failed)"; fail=$((fail+1))
    fi
done
log "Done: $ok ok, $fail failed."
# Restart REQUIRED after paste: the gateway loads auth profiles at BOOT ONLY (scar
# gateway-auth-wrong-door-20260720). Without this, pastes land in a store the running
# process never rereads, and host-side token rotation invalidates its boot snapshot —
# exactly the silent 4-day outage of Jul 16-20 and the relapse of Jul 22.
# Skippable for callers that batch multiple syncs then restart once: OPENAI_SYNC_NO_RESTART=1.
if [ "$ok" -gt 0 ] && [ -z "${OPENAI_SYNC_NO_RESTART:-}" ]; then
    log "Restarting gateway to load pasted tokens (boot-only auth load)..."
    if docker compose -f /root/openclaw/docker-compose.yml restart openclaw-gateway >/dev/null 2>&1; then
        log "Gateway restarted."
    else
        log "Gateway restart FAILED — pasted tokens will NOT be live until a restart happens. Check docker."
    fi
fi
[ "$fail" -eq 0 ]
