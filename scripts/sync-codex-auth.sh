#!/usr/bin/env bash
# sync-codex-auth.sh — Sync Codex CLI OAuth tokens to gateway auth-profiles.json
# Run after `codex auth login` to prevent the "CLI authed but gateway expired" problem.
#
# What it does:
#   1. Reads fresh tokens from ~/.codex/auth.json (CLI)
#   2. Updates /root/.openclaw/agents/main/agent/auth-profiles.json (gateway)
#   3. Restarts gateway to pick up new tokens
#
# Can be triggered:
#   - Manually: sync-codex-auth.sh
#   - Via golden script: host_op="sync-codex-auth"
#   - As post-reauth hook (TODO: wire into codex-reauth.py)

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

# Restart gateway to pick up new tokens
docker compose -f /root/openclaw/docker-compose.yml restart openclaw-gateway 2>&1 | tail -2
sleep 5

# Verify gateway is healthy
HEALTH=$(docker compose -f /root/openclaw/docker-compose.yml ps openclaw-gateway --format '{{.Status}}' 2>/dev/null)
if echo "$HEALTH" | grep -q "healthy"; then
    log "Gateway restarted and healthy"
    echo "SUCCESS: Codex tokens synced, gateway healthy"
else
    log "WARNING: Gateway may not be healthy after restart: $HEALTH"
    echo "WARNING: Check gateway status — $HEALTH"
fi
