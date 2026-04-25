#!/usr/bin/env bash
# fix-codex-auth.sh — THE entry point for Codex auth problems.
#
# WHEN TO USE: Any agent seeing "Codex auth expired", "openai-codex rate-limited",
# or "Provided authentication token is expired" in gateway logs.
#
# WHAT IT DOES:
#   1. Checks if host CLI tokens (~/.codex/auth.json) are still valid
#   2. If valid → syncs them into gateway auth-profiles and restarts (fast path, ~30s)
#   3. If expired → runs full reauth flow (sends device-auth link to Robert via Telegram)
#
# RELATED SCRIPTS (you probably don't need these directly):
#   sync-codex-auth.sh          — just the sync step (called by this script)
#   codex-reauth-telegram.sh    — full reauth + Telegram notification (called by this script)
#   codex-reauth.py             — older Python reauth, use this script instead
#
# Usage:
#   fix-codex-auth.sh            # auto-detect and fix
#   fix-codex-auth.sh --check    # just check status, don't fix

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="/root/.openclaw/logs/fix-codex-auth.log"
AUTH_FILE="$HOME/.codex/auth.json"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$LOG"; }

# --- Check-only mode ---
if [ "${1:-}" = "--check" ]; then
    if [ ! -f "$AUTH_FILE" ]; then
        echo "STATUS: No auth file. Run: fix-codex-auth.sh"
        exit 1
    fi
    VALID=$(python3 -c "
import json, base64, time
with open('$AUTH_FILE') as f:
    auth = json.load(f)
token = auth.get('tokens', auth).get('access_token', '')
if not token or '.' not in token:
    print('no_token'); exit()
payload = token.split('.')[1]
payload += '=' * (4 - len(payload) % 4)
exp = json.loads(base64.urlsafe_b64decode(payload)).get('exp', 0)
remaining_h = (exp - time.time()) / 3600
if remaining_h > 0:
    print(f'valid ({remaining_h:.0f}h remaining)')
else:
    print(f'expired ({-remaining_h:.0f}h ago)')
" 2>&1)
    echo "STATUS: Host tokens $VALID"
    if [[ "$VALID" == valid* ]]; then exit 0; else exit 1; fi
fi

# --- Auto-fix mode ---
log "fix-codex-auth: starting"

# Step 1: Check if host tokens are valid
if [ ! -f "$AUTH_FILE" ]; then
    log "No host auth file — need full reauth"
    exec "$SCRIPT_DIR/codex-reauth-telegram.sh"
fi

HOST_STATUS=$(python3 -c "
import json, base64, time
with open('$AUTH_FILE') as f:
    auth = json.load(f)
token = auth.get('tokens', auth).get('access_token', '')
if not token or '.' not in token:
    print('expired'); exit()
payload = token.split('.')[1]
payload += '=' * (4 - len(payload) % 4)
exp = json.loads(base64.urlsafe_b64decode(payload)).get('exp', 0)
print('valid' if exp > time.time() else 'expired')
" 2>&1)

if [ "$HOST_STATUS" = "valid" ]; then
    # Fast path: host tokens are good, just sync to gateway
    log "Host tokens valid — syncing to gateway (fast path)"
    "$SCRIPT_DIR/sync-codex-auth.sh"
    log "fix-codex-auth: done (fast path)"
    echo "FIXED: Host tokens were valid. Synced to gateway."
else
    # Slow path: host tokens expired too, need full reauth
    log "Host tokens expired — starting full reauth flow"
    echo "Host tokens expired. Starting device auth flow..."
    exec "$SCRIPT_DIR/codex-reauth-telegram.sh"
fi
