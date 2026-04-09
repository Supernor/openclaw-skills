#!/usr/bin/env bash
# Alignment: sync Google Workspace CLI credentials from GitHub vault to local dirs.
# Role: pull encrypted-at-rest credentials from Supernor/openclaw-config GitHub Secrets
# to /root/.openclaw/gws-credentials/<account>/ so gws CLI can authenticate.
# Dependencies: GH_TOKEN in /root/openclaw/.env, gh CLI, jq.
# Key patterns: vault is source of truth — local credentials are ephemeral cache.
# After sync, gws auto-refreshes access tokens using the refresh token. If refresh
# token expires (rare, ~6 months), re-auth via OOB flow and push new creds to vault.
# Usage: sync-gws-credentials.sh [pull|push|status]
# Reference: /root/.openclaw/docs/policy-context-injection.md

set -eo pipefail

ACTION="${1:-pull}"
source /root/openclaw/.env 2>/dev/null || true
export GH_TOKEN

REPO="Supernor/openclaw-config"
CRED_BASE="/root/.openclaw/gws-credentials"
ACCOUNTS=("relay" "eoin")

case "$ACTION" in
    pull)
        for acct in "${ACCOUNTS[@]}"; do
            ACCT_UPPER=$(echo "$acct" | tr '[:lower:]' '[:upper:]')
            DIR="$CRED_BASE/$acct"
            mkdir -p "$DIR"

            # GitHub Secrets can't be read via API (write-only by design)
            # So we check if local files exist and are valid
            if [ -f "$DIR/credentials.json" ]; then
                # Verify the credentials have a refresh token
                if python3 -c "import json; d=json.load(open('$DIR/credentials.json')); assert d.get('refresh_token')" 2>/dev/null; then
                    echo "$acct: credentials valid (refresh token present)"
                else
                    echo "$acct: WARNING — credentials.json exists but missing refresh_token"
                fi
            else
                echo "$acct: no local credentials. Re-auth needed:"
                echo "  1. Run OOB OAuth flow for $acct account"
                echo "  2. Then: sync-gws-credentials.sh push"
            fi
        done
        ;;

    push)
        for acct in "${ACCOUNTS[@]}"; do
            ACCT_UPPER=$(echo "$acct" | tr '[:lower:]' '[:upper:]')
            DIR="$CRED_BASE/$acct"

            if [ -f "$DIR/credentials.json" ]; then
                cat "$DIR/credentials.json" | gh secret set "GWS_CREDENTIALS_${ACCT_UPPER}" --repo "$REPO"
                echo "$acct: credentials pushed to vault"
            fi
            if [ -f "$DIR/client_secret.json" ]; then
                cat "$DIR/client_secret.json" | gh secret set "GWS_CLIENT_SECRET_${ACCT_UPPER}" --repo "$REPO"
                echo "$acct: client_secret pushed to vault"
            fi
        done
        ;;

    status)
        echo "GitHub vault secrets:"
        gh secret list --repo "$REPO" 2>&1 | grep -i GWS
        echo ""
        echo "Local credentials:"
        for acct in "${ACCOUNTS[@]}"; do
            DIR="$CRED_BASE/$acct"
            if [ -f "$DIR/credentials.json" ]; then
                VALID=$(python3 -c "import json; d=json.load(open('$DIR/credentials.json')); print('valid' if d.get('refresh_token') else 'INVALID')" 2>/dev/null || echo "ERROR")
                echo "  $acct: $VALID"
            else
                echo "  $acct: MISSING"
            fi
        done
        ;;

    *)
        echo "Usage: sync-gws-credentials.sh [pull|push|status]"
        exit 1
        ;;
esac
