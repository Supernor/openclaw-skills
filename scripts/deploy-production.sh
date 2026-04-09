#!/usr/bin/env bash
# Alignment: golden script for promoting a site to Cloudflare Pages production.
# Role: deploy approved build to Cloudflare Pages production branch, optionally
# attach a custom domain. Only runs after Robert approves the site on Bridge.
# Dependencies: CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID in /root/openclaw/.env,
# project directory at /root/projects/<project-id>, ops.db design_projects table.
# Key patterns: deploys to the "main" branch (Cloudflare's production branch);
# custom domain added via API if provided; production URL written to ops.db.
# Falls back to *.pages.dev if no custom domain. No Caddy/VPS hosting needed.
# Reference: /root/.openclaw/docs/policy-context-injection.md

set -eo pipefail

PROJECT_ID="${1:?Usage: deploy-production.sh PROJECT_ID [custom-domain]}"
CUSTOM_DOMAIN="${2:-}"
PROJECT_DIR="/root/projects/$PROJECT_ID"

# Load credentials
source /root/openclaw/.env 2>/dev/null || true
if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ACCOUNT_ID" ]; then
    echo "Missing CLOUDFLARE_API_TOKEN or CLOUDFLARE_ACCOUNT_ID in /root/openclaw/.env"
    exit 1
fi

export CLOUDFLARE_API_TOKEN
export CLOUDFLARE_ACCOUNT_ID

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Project not found: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"

# Determine build output directory
BUILD_DIR="$PROJECT_DIR"
if [ -f "package.json" ]; then
    if grep -q '"build"' package.json; then
        npm run build 2>&1 | tail -5
    fi
    for dir in out dist build public; do
        if [ -d "$PROJECT_DIR/$dir" ]; then
            BUILD_DIR="$PROJECT_DIR/$dir"
            break
        fi
    done
fi

# Sanitize project name
CF_PROJECT=$(echo "$PROJECT_ID" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

# Deploy to production branch
DEPLOY_OUTPUT=$(npx wrangler pages deploy "$BUILD_DIR" --project-name "$CF_PROJECT" --branch main 2>&1)
PROD_URL=$(echo "$DEPLOY_OUTPUT" | grep -oP 'https://[^\s]+\.pages\.dev' | tail -1)

if [ -z "$PROD_URL" ]; then
    echo "Cloudflare Pages production deploy failed"
    echo "Output: $DEPLOY_OUTPUT"
    exit 1
fi

# Add custom domain if provided
if [ -n "$CUSTOM_DOMAIN" ]; then
    curl -sf -X POST "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$CF_PROJECT/domains" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$CUSTOM_DOMAIN\"}" \
        > /dev/null 2>&1 && echo "Custom domain added: $CUSTOM_DOMAIN" || echo "Custom domain setup may need DNS verification"
    PROD_URL="https://$CUSTOM_DOMAIN"
fi

# Update ops.db
sqlite3 /root/.openclaw/ops.db "
    UPDATE design_projects
    SET production_url='$PROD_URL', deploy_status='production',
        updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
    WHERE id='$PROJECT_ID'
" 2>/dev/null

echo "Production deployed: $PROD_URL"
echo "$PROD_URL"
