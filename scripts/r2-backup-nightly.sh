#!/bin/bash
# === INTENT ===
# Nightly encrypted offsite backup of /root/.openclaw to Cloudflare R2 (restic).
# The registry/memory (ops.db) is the irreplaceable part; code is also in git.
set -uo pipefail

# === INTENT: staging snapshot (ops.db.snapshot) must be root-only — it lands on the ===
# === bind mount readable by uid-1000 container agents. Added 2026-07-13 per silo ===
# === phase-2 G0. restic repo is separately encrypted (see restic backup below). ===
umask 077

# WHY each piece:
# - creds/password live OUTSIDE git (.r2.env / .restic-password, mode 600)
# - live SQLite (WAL) must never be raw-copied -> consistent .backup snapshot
# - excludes = reinstallable/regenerable trees, keeps us inside the 10GB R2
#   free tier (npm/vendor/update/mcp-servers/extensions/browser/checkpoints/logs)
# - retention 7 daily / 4 weekly / 3 monthly / 5 yearly (yearly added 2026-10-06, backbone B0b: 'for life' needs a restore point older than 3 months)
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
  local text token chat tagged
  text=$(printf '%s' "$1" | tr '\r\n"' '   ')
  # Alert id [A-XXXX] + append-only ops.db alert_log row (shared root-owned helper). Helper always exits 0; any failure => original text, alert still goes out.
  tagged=$(python3 -I /usr/local/lib/knownself-common/alert_log.py tag --source r2-backup-nightly.sh -- "$text" 2>/dev/null) || tagged=""
  [ -n "$tagged" ] && text=$(printf '%s' "$tagged" | tr '\r\n"' '   ')
  if [ -n "${KS_ALERT_SINK:-}" ]; then printf '%s\n' "$text" >> "$KS_ALERT_SINK"; return 0; fi   # lab/test sink
  # .env never had plain TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID — alert path was dead
  # since birth ("alert skipped: no telegram creds" nightly). Robert's real vars +
  # known-good chat id fallback (2026-10-05).
  token=$(grep '^TELEGRAM_BOT_TOKEN=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
  [ -n "${token:-}" ] || token=$(grep '^TELEGRAM_BOT_TOKEN_ROBERT=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
  [ -n "${token:-}" ] || token=$(grep '^TAP_BOT_TOKEN=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
  chat=$(grep '^TELEGRAM_CHAT_ID=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
  [ -n "${chat:-}" ] || chat="8561305605"
  [ -n "${token:-}" ] && [ -n "${chat:-}" ] || { log "alert skipped: no telegram creds"; return 0; }
  printf 'url = "%s/bot%s/sendMessage"\ndata-urlencode = "chat_id=%s"\ndata-urlencode = "text=%s"\n' \
    "${KS_TG_API_BASE:-https://api.telegram.org}" "$token" "$chat" "$text" | { code=$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' -K - 2>/dev/null) || code=""; \
      aid=$(printf '%s' "$text" | sed -n 's/^\[\(A-[A-Z0-9]\{4\}\)\].*/\1/p' | head -1); \
      [ -n "$aid" ] && python3 -I /usr/local/lib/knownself-common/alert_log.py deliver --alert-id "$aid" --channel telegram --http "${code:-}" --ok "$([ "${code:-}" = 200 ] && echo 1 || echo 0)" --detail "r2-backup alert" >/dev/null 2>&1; true; }   # [alert-signal-cleanup 2026-10-28] delivery ledger row
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

# 1b) [alert-hygiene 2026-10-22] transcripts.db and scope.db are live WAL SQLite files whose -wal/-shm sidecars vanish mid-scan
# (restic: "lstat ...-wal: no such file") and raised a nightly "unreadable files" warning. The sidecars are now excluded below, so a
# consistent .backup copy of each DB goes to staging (staging rides in the main backup via /root/.openclaw/backups). If a copy fails
# we say so loudly rather than silently losing WAL-resident rows.
for _db in transcripts scope; do
  if [ -f "/root/.openclaw/${_db}.db" ]; then
    sqlite3 "/root/.openclaw/${_db}.db" ".timeout 5000" ".backup '$STAGING/${_db}.db.snapshot'" 2>>"$LOG" \
      || { log "WARN: sqlite .backup of ${_db}.db failed; its -wal is excluded from restic, so recent rows may be missing from tonight's backup"; \
           telegram_alert "r2-backup WARNING: could not make a consistent snapshot of ${_db}.db (see ${LOG}); its WAL file is excluded from the backup, so the newest rows may be missing tonight."; }
  fi
done

# 2) Encrypted incremental backup
R2_RUN_LOG_START=$(wc -l < "$LOG" 2>/dev/null || echo 0)
restic backup /root/.openclaw \
  --exclude /root/.openclaw/transcripts.db-wal \
  --exclude /root/.openclaw/transcripts.db-shm \
  --exclude /root/.openclaw/scope.db-wal \
  --exclude /root/.openclaw/scope.db-shm \
  --exclude /root/.openclaw/tmp/plugin-captures \
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
  >> "$LOG" 2>&1
rc=$?
# restic exit 3 = snapshot CREATED but some files unreadable (normal at 03:30 —
# other crons hold wal/lock files). Treating 3 as fatal inverted the honest
# signal for weeks: real snapshots reported as FAIL (fixed 2026-10-05).
if [ "$rc" -eq 3 ]; then
  R2_WARN_TEXT=$(python3 -I -B /root/.openclaw/scripts/r2-restic-warning.py "$LOG" "$R2_RUN_LOG_START" 2>/dev/null) || R2_WARN_TEXT="restic exit 3 (could not name the files; see ${LOG})"
  log "WARN: ${R2_WARN_TEXT}. Counting as OK-with-warning."
  telegram_alert "r2-backup WARNING: ${R2_WARN_TEXT}. Snapshot was created and is usable."
elif [ "$rc" -ne 0 ]; then
  fail "restic backup (exit $rc)"
fi
# NOTE: live ops.db is EXCLUDED on purpose — $STAGING/ops.db.snapshot (included
# via /root/.openclaw/backups) is the consistent copy a restore should use.
restic backup "$STAGING/ops.db.snapshot" >> "$LOG" 2>&1 || fail "restic backup of ops.db snapshot"

# === INTENT: KnownSelf backbone (design v1.1 B0b, judge finding 7): the archive of every external-AI message/proposal, the root decision ledger,
# === approval secrets and policy config live OUTSIDE /root/.openclaw. They are append-only lifelong evidence, so they ride this nightly job. ===
# rc 3 = snapshot created, some files unreadable (same honest handling as the main backup above).
# B8 (2026-10-06): + secrets/ (approval-bot.token, alert.conf, audit-salt, token-hashes). The restic repo is encrypted; losing the bot token = re-run BotFather, losing audit-salt breaks hash continuity.
# OAuth L4 C5(c) (2026-10-07): + /srv/knownself-public/oauth (HMAC keys, client secret hash, internal bearer copy: the grant ledger itself lives under state/oauth and is already covered). Added only when the directory exists, so the nightly
# run before the OAuth deploy neither warns nor fails. A restore from a snapshot older than grant_created strands ChatGPT (re-login): see oauth-staging/deploy/DEPLOY.md "post-grant manual backup".
KS_BACKUP_PATHS="/srv/knownself-public/state /srv/knownself-public/config /srv/knownself-public/secrets"
[ -d /srv/knownself-public/oauth ] && KS_BACKUP_PATHS="$KS_BACKUP_PATHS /srv/knownself-public/oauth"
# Page metadata uses WAL. Preserve it with the host's locked SQLite backup API,
# alongside every blob/version. Do not raw-copy a live page database into restic.
PAGE_SNAPSHOT=""
if [ -f /srv/knownself-public/state/pages/pages.db ]; then
  PAGE_SNAPSHOT="$STAGING/pages-$(date -u +%Y%m%dT%H%M%SZ)"
  python3 -I -B /srv/knownself-public/backbone/pages.py --backup "$PAGE_SNAPSHOT" >> "$LOG" 2>&1 || fail "page SQLite/blob backup bundle"
fi
# docs-own-db 2026-10-28 (judge F1): KnownSelf documents live in state/docdb/documents.db. Same rule as pages.db: NEVER raw-copy a live SQLite
# file into restic. A consistent .backup goes to staging (backed up as its own single-file snapshot below, like ops.db.snapshot), raw file+journal excluded.
if [ -f /srv/knownself-public/state/docdb/documents.db ]; then
  sqlite3 /srv/knownself-public/state/docdb/documents.db ".timeout 5000" ".backup '$STAGING/documents.db.snapshot'" 2>>"$LOG" || fail "sqlite .backup of documents.db (lifelong documents store)"
fi
restic backup $KS_BACKUP_PATHS \
  --exclude /srv/knownself-public/state/docdb/documents.db \
  --exclude /srv/knownself-public/state/docdb/documents.db-journal \
  --exclude /srv/knownself-public/state/pages/pages.db \
  --exclude /srv/knownself-public/state/pages/pages.db-wal \
  --exclude /srv/knownself-public/state/pages/pages.db-shm >> "$LOG" 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then
  log "WARN: knownself-public restic exit 3 — snapshot created, some files unreadable."
elif [ "$rc" -ne 0 ]; then
  fail "restic backup of /srv/knownself-public state+config+secrets (exit $rc)"
fi

if [ -f "$STAGING/documents.db.snapshot" ]; then
  restic backup "$STAGING/documents.db.snapshot" >> "$LOG" 2>&1 || fail "restic backup of documents.db snapshot"
fi

if [ -n "$PAGE_SNAPSHOT" ]; then
  restic backup "$PAGE_SNAPSHOT" >> "$LOG" 2>&1 || fail "restic backup of verified page bundle"
fi

# 3) Retention + light integrity check (5% data read, rotates by day)
# === INTENT: hardening 2026-10-13 (#822): stale repo lock (dead PID, same host, >2h) blocked prune 10-09..10-13 unnoticed. Clear dead-owner locks first; escalate if prune fails 2 nights running. ===
python3 -I -B /root/.openclaw/scripts/r2-lock-hygiene.py >> "$LOG" 2>&1 || log "WARN: lock hygiene could not clear a lock (see line above); prune may fail"
restic forget --keep-tag offload-keep --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --keep-yearly unlimited --prune >> "$LOG" 2>&1 || { PF=$(python3 -c "
import sqlite3
c=sqlite3.connect('$OPS_DB',timeout=6);k='r2-prune-fail-count'
r=c.execute('select value from kv where key=?',(k,)).fetchone();n=int(r[0])+1 if r and str(r[0]).isdigit() else 1
c.execute(\"INSERT OR REPLACE INTO kv(key,value,updated_at) VALUES(?,?,strftime('%Y-%m-%dT%H:%M:%SZ','now'))\",(k,str(n)));c.commit();print(n)" 2>/dev/null || echo 1)
  if [ "${PF:-1}" -ge 2 ]; then telegram_alert "HIGH: r2 prune has failed ${PF} nights running. WHAT: restic forget/prune error (see ${LOG}). WHY: repo grows unbounded; snapshots still save. HOW TO FIX: source /root/.openclaw/.r2.env; restic list locks; restic unlock (stale only); rerun r2-backup-nightly.sh. WHAT WORKED BEFORE: restic unlock cleared dead-PID lock 2217327 on 2026-10-13."; fi
  fail "restic forget/prune (consecutive failures: ${PF:-1})"; }
kv_write 'r2-prune-fail-count' 0 || true
restic check --read-data-subset=5% >> "$LOG" 2>&1 || fail "restic check"

kv_write 'r2-backup-state' "ok $(date -u +%FT%TZ)" \
  || log "WARN: kv write of ok-state failed — kv may hold stale value (backup itself succeeded)"
log "=== r2-backup OK ==="
