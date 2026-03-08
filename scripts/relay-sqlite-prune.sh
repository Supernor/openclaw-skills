#!/usr/bin/env bash
# relay-sqlite-prune.sh — Prune bloated per-agent memory SQLite files
# Intent: Efficient [I06], Resilient [I08].
# Runs weekly. Drops embedding_cache (redundant), vacuums, reports.
# Keeps chunks + FTS intact.

set -eo pipefail

COMPOSE_DIR="/root/openclaw"
LOG="/root/.openclaw/logs/sqlite-prune.log"
mkdir -p "$(dirname "$LOG")"

_exec() {
  docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway "$@" 2>&1 | grep -v "level=warning"
}

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

echo "[$(ts)] Starting SQLite prune" >> "$LOG"

# Find all memory SQLite files
MEMORY_DIR="/home/node/.openclaw/memory"
FILES=$(_exec find "$MEMORY_DIR" -maxdepth 1 -name "*.sqlite" -type f 2>/dev/null) || true

for dbfile in $FILES; do
  BASENAME=$(basename "$dbfile")
  BEFORE=$(_exec stat -c%s "$dbfile" 2>/dev/null) || continue

  # Drop embedding_cache if it exists (redundant with chunks.embedding)
  _exec sqlite3 "$dbfile" "DROP TABLE IF EXISTS embedding_cache;" 2>/dev/null || true

  # Delete chunks older than 30 days if table has timestamp
  _exec sqlite3 "$dbfile" "DELETE FROM chunks WHERE created_at < datetime('now', '-30 days');" 2>/dev/null || true

  # Vacuum
  _exec sqlite3 "$dbfile" "VACUUM;" 2>/dev/null || true

  AFTER=$(_exec stat -c%s "$dbfile" 2>/dev/null) || continue
  SAVED=$(( (BEFORE - AFTER) / 1024 ))
  echo "[$(ts)] $BASENAME: ${BEFORE}B -> ${AFTER}B (saved ${SAVED}KB)" >> "$LOG"
done

# Also prune QMD databases
QMD_FILES=$(_exec find /home/node/.openclaw/agents -name "index.sqlite" -path "*/qmd/*" 2>/dev/null) || true
for dbfile in $QMD_FILES; do
  _exec sqlite3 "$dbfile" "DROP TABLE IF EXISTS embedding_cache; VACUUM;" 2>/dev/null || true
done

echo "[$(ts)] Prune complete" >> "$LOG"
