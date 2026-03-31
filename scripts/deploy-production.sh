#!/usr/bin/env bash
# deploy-production.sh — Deploy approved site to VPS via Caddy.
# Only runs after Robert approves the full site.
#
# Usage: deploy-production.sh <project-id> [domain]
# Requires: Caddy installed, site approved on Bridge.

set -eo pipefail

PROJECT_ID="${1:?Usage: deploy-production.sh PROJECT_ID [domain]}"
DOMAIN="${2:-$PROJECT_ID.localhost}"
PROJECT_DIR="/root/projects/$PROJECT_ID"
SERVE_DIR="/var/www/$PROJECT_ID"
CADDY_FILE="/etc/caddy/Caddyfile"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Project not found: $PROJECT_DIR"
    exit 1
fi

# Build if needed
cd "$PROJECT_DIR"
if [ -f "package.json" ] && grep -q '"build"' package.json; then
    npm run build 2>&1 | tail -5
    BUILD_OUTPUT="$PROJECT_DIR/.next/static"
    # For static export
    if [ -d "$PROJECT_DIR/out" ]; then
        BUILD_OUTPUT="$PROJECT_DIR/out"
    elif [ -d "$PROJECT_DIR/dist" ]; then
        BUILD_OUTPUT="$PROJECT_DIR/dist"
    fi
else
    BUILD_OUTPUT="$PROJECT_DIR"
fi

# Copy to serve directory
mkdir -p "$SERVE_DIR"
rsync -a --delete "$BUILD_OUTPUT/" "$SERVE_DIR/"
echo "Files copied to $SERVE_DIR"

# Add Caddy site block if not already present
if ! grep -q "$PROJECT_ID" "$CADDY_FILE" 2>/dev/null; then
    mkdir -p /etc/caddy
    cat >> "$CADDY_FILE" << CADDY

# $PROJECT_ID — deployed $(date -u +%Y-%m-%dT%H:%M:%SZ)
$DOMAIN {
    root * $SERVE_DIR
    file_server
    encode gzip
}
CADDY
    echo "Added Caddy config for $DOMAIN"
fi

# Reload Caddy
caddy reload --config "$CADDY_FILE" 2>/dev/null || caddy start --config "$CADDY_FILE" 2>/dev/null
echo "Caddy reloaded"

# Update ops.db
sqlite3 /root/.openclaw/ops.db "
    UPDATE design_projects
    SET production_url='https://$DOMAIN', deploy_status='production',
        updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
    WHERE id='$PROJECT_ID'
" 2>/dev/null

echo "Production deployed: $DOMAIN → $SERVE_DIR"
