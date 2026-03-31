#!/usr/bin/env bash
# deploy-preview.sh — Build and deploy to Vercel preview.
# Returns a preview URL that Robert reviews on his phone.
#
# Usage: deploy-preview.sh <project-id>
# Requires: vercel CLI installed and linked to project.

set -eo pipefail

PROJECT_ID="${1:?Usage: deploy-preview.sh PROJECT_ID}"
PROJECT_DIR="/root/projects/$PROJECT_ID"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Project not found: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"

# Build if package.json exists (Next.js etc)
if [ -f "package.json" ]; then
    npm run build 2>&1 | tail -5
fi

# Deploy to Vercel (preview, not production)
# --yes to skip prompts, --no-clipboard to avoid display issues
PREVIEW_URL=$(vercel --yes --no-clipboard 2>&1 | grep -oP 'https://[^ ]+\.vercel\.app' | tail -1)

if [ -z "$PREVIEW_URL" ]; then
    echo "Vercel deploy failed — no preview URL returned"
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
