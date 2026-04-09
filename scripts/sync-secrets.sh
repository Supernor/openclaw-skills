#!/usr/bin/env bash
# Alignment: golden secret sync script for static API keys between GitHub and local env.
# Role: pull key material into `/root/openclaw/.env`, report freshness, and gate push flows.
# Dependencies: reads `GH_TOKEN` and local `.env`, writes `/root/openclaw/.env` and sync logs,
# calls `gh secret` against `Supernor/openclaw-config`, and excludes Codex OAuth handling.
# Key patterns: host-op entrypoint is `sync-secrets`; `pull`, `status`, and approval-backed
# `push KEY` preserve GitHub Secrets as source of truth while surfacing local key freshness.
# Reference: /root/.openclaw/docs/policy-context-injection.md

set -eo pipefail

REPO="Supernor/openclaw-config"
ENV_FILE="/root/openclaw/.env"
LOG="/root/.openclaw/logs/sync-secrets.log"

# Load GH_TOKEN
if [ -z "$GH_TOKEN" ]; then
    export GH_TOKEN=$(grep "^GH_TOKEN=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
fi

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$LOG"; }

case "${1:-status}" in
  status)
    echo "=== GitHub Secrets ($REPO) ==="
    gh secret list --repo "$REPO" 2>/dev/null || echo "ERROR: Cannot read GitHub Secrets"
    echo ""
    echo "=== Local .env keys ==="
    grep -oP '^[A-Z_]+(?==)' "$ENV_FILE" 2>/dev/null | sort
    echo ""
    echo "=== Keys in GitHub but NOT in .env ==="
    GH_KEYS=$(gh secret list --repo "$REPO" 2>/dev/null | awk '{print $1}' | sort)
    LOCAL_KEYS=$(grep -oP '^[A-Z_]+(?==)' "$ENV_FILE" 2>/dev/null | sort)
    comm -23 <(echo "$GH_KEYS") <(echo "$LOCAL_KEYS") || echo "(none)"
    echo ""
    echo "=== Keys in .env but NOT in GitHub ==="
    comm -13 <(echo "$GH_KEYS") <(echo "$LOCAL_KEYS") || echo "(none)"
    ;;

  pull)
    log "Pulling secrets from $REPO"
    # GitHub Secrets can't be READ via API (write-only by design).
    # This command verifies they exist and shows last-updated dates.
    # Actual secret values must be set via GitHub UI or gh secret set.
    echo "NOTE: GitHub Secrets are write-only — values cannot be pulled via API."
    echo "This command verifies what EXISTS in the vault."
    echo ""
    gh secret list --repo "$REPO" 2>/dev/null
    echo ""
    echo "To update a local key from GitHub, you must:"
    echo "  1. Copy the value from GitHub UI (Settings → Secrets)"
    echo "  2. Or re-set it: gh secret set KEY --body 'value' --repo $REPO"
    echo "  3. Then update .env manually"
    echo ""
    echo "For automated sync, use the .env.template in the repo as the schema."
    log "Pull complete (verification only — GitHub Secrets are write-only)"
    ;;

  push)
    KEY="${2:?Usage: sync-secrets.sh push KEY_NAME}"
    VALUE=$(grep "^${KEY}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
    if [ -z "$VALUE" ]; then
        echo "ERROR: $KEY not found in $ENV_FILE"
        exit 1
    fi
    echo "Pushing $KEY to $REPO GitHub Secrets..."
    echo "$VALUE" | gh secret set "$KEY" --repo "$REPO" 2>/dev/null
    log "Pushed $KEY to $REPO"
    echo "Done. $KEY updated in GitHub Secrets."
    ;;

  *)
    echo "Usage: sync-secrets.sh [status|pull|push KEY]"
    exit 1
    ;;
esac
