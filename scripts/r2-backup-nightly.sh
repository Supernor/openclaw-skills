#!/bin/bash
# === INTENT ===
# Nightly encrypted offsite backup of /root/.openclaw to Cloudflare R2 (restic).
# The registry/memory (ops.db) is the irreplaceable part; code is also in git.
set -uo pipefail

# WHY each piece:
# - creds/password live OUTSIDE git (.r2.env / .restic-password, mode 600)
# - live SQLite (WAL) must never be raw-copied -> consistent .backup snapshot
# - excludes = reinstallable/regenerable trees, keeps us inside the 10GB R2
#   free tier (npm/vendor/update/mcp-servers/extensions/browser/checkpoints/logs)
# - retention 7 daily / 4 weekly / 3 monthly
# - alert path must not depend on the thing being monitored -> telegram_direct
#   pattern (same as stability-monitor.sh), state-change only via ops.db kv

source /root/.openclaw/.r2.env

LOG=/root/.openclaw/logs/r2-backup.log
STAGING=/root/.openclaw/backups/r2-staging
OPS_DB=/root/.openclaw/ops.db
mkdir -p "$STAGING" /root/.openclaw/logs

log() { echo "$(date -u +%FT%TZ) $*" >> "$LOG"; }

# kv_write: parameterized + checked (busy_timeout so a locked DB waits, not fails).
kv_write() {
  python3 - "$OPS_DB" "$1" "$2" <<'PY'
import sys, sqlite3
db, key, val = sys.argv[1:4]
try:
    c = sqlite3.connect(db, timeout=6)
    c.execute("PRAGMA busy_timeout=5000")
    c.execute("INSERT OR REPLACE INTO kv(key,value,updated_at) "
              "VALUES(?,?,strftime('%Y-%m-%dT%H:%M:%SZ','now'))", (key, val))
    c.commit(); c.close()
except Exception as e:
    sys.stderr.write("kv_write failed: %s" % e); sys.exit(1)
PY
}

# telegram_direct pattern: bypasses the gateway. Token fed to curl via stdin config
# (-K -), never on the command line, so it can't appear in the process listing.
telegram_alert() {
  local text token chat
  text=$(printf '%s' "$1" | tr '\r\n"' '   ')
  token=$(grep '^TELEGRAM_BOT_TOKEN=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
  chat=$(grep '^TELEGRAM_CHAT_ID=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
  [ -n "${token:-}" ] && [ -n "${chat:-}" ] || { log "alert skipped: no telegram creds"; return 0; }
  printf 'url = "https://api.telegram.org/bot%s/sendMessage"\ndata-urlencode = "chat_id=%s"\ndata-urlencode = "text=%s"\n' \
    "$token" "$chat" "$text" | curl -sS --max-time 20 -K - >/dev/null 2>&1 || true
}

fail() {
  # Teaching error shape: WHAT / HISTORY / NOT-TRIED / WHAT-WORKED
  local what="$1"
  log "FAIL: $what"
  kv_write 'r2-backup-state' "failed: $what ($(date -u +%FT%TZ))" \
    || log "WARN: kv write of failed-state ALSO failed — kv may hold stale value; alerting anyway"
  telegram_alert "r2-backup FAILED: ${what}. History: check ${LOG}. Not tried: restic unlock, manual re-run. Last fix: see scar on r2-backup-nightly.sh."
  exit 1
}

log "=== r2-backup start ==="

# 1) Consistent snapshot of the live WAL database
sqlite3 "$OPS_DB" ".backup '$STAGING/ops.db.snapshot'" || fail "sqlite .backup of ops.db"

# 2) Encrypted incremental backup
restic backup /root/.openclaw \
  --exclude /root/.openclaw/npm \
  --exclude /root/.openclaw/vendor \
  --exclude /root/.openclaw/update \
  --exclude /root/.openclaw/mcp-servers \
  --exclude /root/.openclaw/extensions \
  --exclude /root/.openclaw/browser \
  --exclude /root/.openclaw/checkpoints \
  --exclude /root/.openclaw/logs \
  --exclude "$OPS_DB" \
  --exclude "${OPS_DB}-wal" \
  --exclude "${OPS_DB}-shm" \
  --exclude "/root/.openclaw/backups/r2-staging" \
  >> "$LOG" 2>&1 || fail "restic backup"
# NOTE: live ops.db is EXCLUDED on purpose — $STAGING/ops.db.snapshot (included
# via /root/.openclaw/backups) is the consistent copy a restore should use.
restic backup "$STAGING/ops.db.snapshot" >> "$LOG" 2>&1 || fail "restic backup of ops.db snapshot"

# 3) Retention + light integrity check (5% data read, rotates by day)
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune >> "$LOG" 2>&1 || fail "restic forget/prune"
restic check --read-data-subset=5% >> "$LOG" 2>&1 || fail "restic check"

kv_write 'r2-backup-state' "ok $(date -u +%FT%TZ)" \
  || log "WARN: kv write of ok-state failed — kv may hold stale value (backup itself succeeded)"
log "=== r2-backup OK ==="
