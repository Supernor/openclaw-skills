#!/bin/bash
# Rollback OpenClaw update — restore pre-update state
set -eo pipefail

BACKUP_DIR="/root/.openclaw/backups/pre-update-$(date +%Y%m%d)"
echo "=== OpenClaw Update Rollback ==="
echo "Backup dir: $BACKUP_DIR"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "ERROR: No backup found at $BACKUP_DIR"
    exit 1
fi

echo "1. Stopping gateway..."
cd /root/openclaw
docker compose down

echo "2. Reverting git..."
git stash

echo "3. Restoring config..."
cp "$BACKUP_DIR/openclaw.json" /root/.openclaw/openclaw.json
chown 1000:1000 /root/.openclaw/openclaw.json

echo "4. Restoring databases..."
cp "$BACKUP_DIR/ops.db" /root/.openclaw/ops.db
cp "$BACKUP_DIR/transcripts.db" /root/.openclaw/transcripts.db
[ -f "$BACKUP_DIR/telegram-transcript.db" ] && cp "$BACKUP_DIR/telegram-transcript.db" /root/.openclaw/telegram-transcript.db

echo "5. Rebuilding and starting..."
docker compose up -d

echo "6. Restarting services..."
systemctl restart openclaw-host-ops relay-handoff-watcher openclaw-bridge-dev

echo "7. Waiting for startup..."
sleep 15

echo "8. Health check..."
docker compose exec -T openclaw-gateway openclaw health 2>/dev/null | head -5

echo "=== Rollback complete ==="
