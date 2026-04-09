#!/usr/bin/env bash
# Alignment: golden script for deploying site previews via Cloudflare Pages.
# Role: upload a project's build output to Cloudflare Pages, return a preview URL.
# Dependencies: CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID in /root/openclaw/.env,
# project directory at /root/projects/<project-id>, ops.db design_projects table.
# Key patterns: auto-creates the Pages project if it doesn't exist; uploads via
# Wrangler CLI (direct upload, no git integration); preview URL written to ops.db
# so Bridge can display it. Production deploys use deploy-production.sh instead.
# Reference: /root/.openclaw/docs/policy-context-injection.md

set -eo pipefail

PROJECT_ID="${1:?Usage: deploy-preview.sh PROJECT_ID}"
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
    # Check common build output dirs
    for dir in out dist build public; do
        if [ -d "$PROJECT_DIR/$dir" ]; then
            BUILD_DIR="$PROJECT_DIR/$dir"
            break
        fi
    done
fi

# Sanitize project name for Cloudflare (lowercase, alphanumeric + hyphens)
CF_PROJECT=$(echo "$PROJECT_ID" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

# Create Pages project if it doesn't exist (API call, no UI needed)
curl -sf -X POST "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$CF_PROJECT\", \"production_branch\": \"main\"}" \
    > /dev/null 2>&1 || true  # Ignore error if project already exists

# Deploy via Wrangler (direct upload — no git needed)
DEPLOY_OUTPUT=$(npx wrangler pages deploy "$BUILD_DIR" --project-name "$CF_PROJECT" --branch preview 2>&1)
PREVIEW_URL=$(echo "$DEPLOY_OUTPUT" | grep -oP 'https://[^\s]+\.pages\.dev' | tail -1)

if [ -z "$PREVIEW_URL" ]; then
    echo "Cloudflare Pages deploy failed — no preview URL returned"
    echo "Output: $DEPLOY_OUTPUT"
    exit 1
fi

# Update ops.db with preview URL
sqlite3 /root/.openclaw/ops.db "
    UPDATE design_projects
    SET preview_url='$PREVIEW_URL', deploy_status='preview',
        updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
    WHERE id='$PROJECT_ID'
" 2>/dev/null

echo "Preview deployed: $PREVIEW_URL"
echo "$PREVIEW_URL"
