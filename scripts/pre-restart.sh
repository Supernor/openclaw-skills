#!/usr/bin/env bash
# pre-restart.sh — Backup config before gateway restart
# Usage: pre-restart.sh [reason]
# Intent: Recoverable [I09]. Created: 2026-03-09.
set -eo pipefail

BASE="/root/.openclaw"
BACKUP_DIR="${BASE}/config-backups"
TS=$(date -u +%Y%m%d-%H%M%S)
REASON="${1:-manual}"

mkdir -p "$BACKUP_DIR"

# Backup openclaw.json
if [ -f "${BASE}/openclaw.json" ]; then
    cp "${BASE}/openclaw.json" "${BACKUP_DIR}/openclaw.json.${TS}"
    echo "Backed up openclaw.json -> openclaw.json.${TS} (reason: ${REASON})"
fi

# Backup helm-config.json
if [ -f "${BASE}/helm-config.json" ]; then
    cp "${BASE}/helm-config.json" "${BACKUP_DIR}/helm-config.json.${TS}"
fi

# Prune: keep only last 10 backups per file
for PREFIX in openclaw.json helm-config.json; do
    ls -1t "${BACKUP_DIR}/${PREFIX}."* 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
done
