#!/usr/bin/env bash
# sync-codex-auth.sh — SYNC ONLY: copies host CLI tokens into gateway auth-profiles.
#
# NOTE FOR AGENTS: This is the SYNC step only. If you're trying to FIX Codex auth,
# use fix-codex-auth.sh instead — it checks host tokens first and calls this script
# if they're valid, or runs full reauth if they're not.
#
#   fix-codex-auth.sh  ← start here (auto-detects and fixes)
#   sync-codex-auth.sh ← you are here (sync only, assumes host tokens are valid)
#   codex-reauth-telegram.sh ← full reauth flow (sends link to Robert)
#
# Role: keeps gateway authentication aligned with fresh Codex CLI reauth state.
# Dependencies: reads ~/.codex/auth.json, writes auth-profiles.json, restarts gateway.
# Reference: /root/.openclaw/docs/policy-context-injection.md

set -eo pipefail

CLI_AUTH="$HOME/.codex/auth.json"
GATEWAY_AUTH="/root/.openclaw/agents/main/agent/auth-profiles.json"
LOG="/root/.openclaw/logs/sync-codex-auth.log"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$LOG"; }

if [ ! -f "$CLI_AUTH" ]; then
    log "ERROR: $CLI_AUTH not found. Run 'codex auth login' first."
    exit 1
fi

if [ ! -f "$GATEWAY_AUTH" ]; then
    log "ERROR: $GATEWAY_AUTH not found."
    exit 1
fi

# Sync tokens
python3 -c "
import json, time

with open('$CLI_AUTH') as f:
    cli = json.load(f)

tokens = cli.get('tokens', cli)
access = tokens.get('access_token', '')
refresh = tokens.get('refresh_token', '')
account_id = tokens.get('account_id', '')

if not access:
    print('ERROR: No access_token in CLI auth')
    exit(1)

with open('$GATEWAY_AUTH') as f:
    profiles = json.load(f)

new_expiry = int((time.time() + 10 * 86400) * 1000)  # 10 days
updated = []

for pool_name in list(profiles.get('profiles', {})):
    if 'codex' in pool_name.lower():
        profiles['profiles'][pool_name]['access'] = access
        profiles['profiles'][pool_name]['refresh'] = refresh
        profiles['profiles'][pool_name]['expires'] = new_expiry
        if account_id:
            profiles['profiles'][pool_name]['accountId'] = account_id
        updated.append(pool_name)

with open('$GATEWAY_AUTH', 'w') as f:
    json.dump(profiles, f, indent=2)

for p in updated:
    print(f'Updated {p}')
print(f'Token expires: {time.strftime(\"%Y-%m-%d %H:%M UTC\", time.gmtime(new_expiry/1000))}')
"
SYNC_EXIT=$?

if [ $SYNC_EXIT -ne 0 ]; then
    log "ERROR: Token sync failed"
    exit 1
fi

log "Tokens synced to gateway auth-profiles"

# Restart gateway safely (notifies user, polls for health)
/root/.openclaw/scripts/gateway-restart-safe.sh "8561305605" "Codex tokens synced" 2>&1 | tail -3
if [ $? -eq 0 ]; then
    log "Gateway restarted and healthy"
    echo "SUCCESS: Codex tokens synced, gateway healthy"
else
    log "WARNING: Gateway restart may have issues"
    echo "WARNING: Check gateway status"
fi
