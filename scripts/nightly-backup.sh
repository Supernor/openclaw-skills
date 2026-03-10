#!/usr/bin/env bash
# nightly-backup.sh — Automated nightly backup of critical OpenClaw data
# Cron: 0 3 * * * /root/.openclaw/scripts/nightly-backup.sh
# Intent: Recoverable [I09]. Created: 2026-03-09.
set -eo pipefail

BASE="/root/.openclaw"
BACKUP_ROOT="${BASE}/backups"
TODAY=$(date -u +%Y-%m-%d)
BACKUP_DIR="${BACKUP_ROOT}/${TODAY}"
LOG="${BASE}/logs/nightly-backup.log"
RETENTION_DAYS=7

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >> "$LOG"; }

mkdir -p "$BACKUP_DIR" "$(dirname "$LOG")"
log "Starting nightly backup to ${BACKUP_DIR}"

# 1. Dump critical SQLite databases (using .backup for consistency)
DATABASES=(
    "ops.db"
    "bridge/reactor-ledger.sqlite"
    "transcripts.db"
    "telegram-transcript.db"
    "engine-trust.db"
    "taint.db"
    "memory/lancedb/chartroom.sqlite"
)

DB_COUNT=0
for DB_REL in "${DATABASES[@]}"; do
    DB_PATH="${BASE}/${DB_REL}"
    if [ -f "$DB_PATH" ]; then
        DB_NAME=$(basename "$DB_REL")
        sqlite3 "$DB_PATH" ".backup '${BACKUP_DIR}/${DB_NAME}'" 2>/dev/null && {
            DB_COUNT=$((DB_COUNT + 1))
            log "  DB: ${DB_REL} -> ${DB_NAME}"
        } || log "  DB FAILED: ${DB_REL}"
    fi
done

# 2. Copy critical config files
CONFIGS=(
    "openclaw.json"
    "helm-config.json"
    "model-aliases.json"
    "agent-roster.json"
    "capabilities.json"
)

mkdir -p "${BACKUP_DIR}/configs"
CFG_COUNT=0
for CFG in "${CONFIGS[@]}"; do
    if [ -f "${BASE}/${CFG}" ]; then
        cp "${BASE}/${CFG}" "${BACKUP_DIR}/configs/"
        CFG_COUNT=$((CFG_COUNT + 1))
    fi
done

# 3. Copy auth profiles
AUTH_SRC="${BASE}/agents/main/agent/auth-profiles.json"
if [ -f "$AUTH_SRC" ]; then
    mkdir -p "${BACKUP_DIR}/auth"
    cp "$AUTH_SRC" "${BACKUP_DIR}/auth/"
    log "  Auth profiles backed up"
fi

# 4. Copy LanceDB vector data (skip sqlite, already backed up above)
if [ -d "${BASE}/memory/lancedb" ]; then
    mkdir -p "${BACKUP_DIR}/lancedb"
    # Copy .lance directories (vector indices)
    find "${BASE}/memory/lancedb" -name "*.lance" -type d -exec cp -r {} "${BACKUP_DIR}/lancedb/" \; 2>/dev/null
    log "  LanceDB vector data backed up"
fi

# 5. Compute backup size
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
log "Backup complete: ${DB_COUNT} DBs, ${CFG_COUNT} configs, size=${BACKUP_SIZE}"

# 6. Prune old backups (retain RETENTION_DAYS days)
PRUNED=0
find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -mtime +${RETENTION_DAYS} | while read OLD_DIR; do
    rm -rf "$OLD_DIR"
    log "  Pruned old backup: $(basename "$OLD_DIR")"
    PRUNED=$((PRUNED + 1))
done

log "Nightly backup finished. Retention: ${RETENTION_DAYS} days."
echo "{\"status\":\"ok\",\"date\":\"${TODAY}\",\"dbs\":${DB_COUNT},\"configs\":${CFG_COUNT},\"size\":\"${BACKUP_SIZE}\"}"
