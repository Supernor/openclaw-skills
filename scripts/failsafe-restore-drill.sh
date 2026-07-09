#!/bin/bash
# === INTENT ===
# Weekly PROOF that the offsite backup can actually be restored: pull the latest
# ops.db.snapshot back from R2, verify its SQLite integrity + schema + referential
# health, and confirm its critical-table counts track the live DB. A backup that is
# never restored is UNVERIFIED, not healthy — this script is what earns "healthy".
set -uo pipefail

# WHY each piece:
# - We restore the ops.db.snapshot SNAPSHOT (the consistent .backup copy), not the
#   live WAL DB, because the live file is excluded from the R2 backup on purpose.
# - PROPORTIONATE proof bar = integrity_check + schema-DDL-hash match + table-count
#   match + foreign_key_check (not worse than live) + counts of TWO critical tables
#   (mem_nodes, mem_edges, tasks) within tolerance. WHY this and not content hashes:
#   integrity catches page corruption; schema-DDL-hash+table-count catch schema drift
#   / a truncated or wrong-era restore; fk_check catches structural rot; two-table
#   counts catch a restore that silently dropped a table. Content/row hashes would be
#   gold-plating — the snapshot legitimately drifts from live between backup and now,
#   so a hash mismatch is expected noise, not signal. This bar is falsifiable and
#   cheap; it fails RED on a bad restore and cannot pass GREEN on an empty/wrong DB.
# - fk_check is judged as "no WORSE than the live DB" because the live DB may carry a
#   known pre-existing violation; the drill proves the restore added no new breakage,
#   it is not a live-DB linter.
# - kv writes are PARAMETERIZED + CHECKED via python sqlite3 (busy_timeout=5000). A
#   failed state write must never leave a stale 'ok' behind: the success path routes
#   a kv-write failure into fail(), which alerts and exits nonzero (fail-closed).
# - Alert path (telegram_alert) bypasses the gateway (mirrors r2-backup-nightly.sh):
#   the thing we monitor must never be the thing that has to be up to warn us. The
#   bot token is fed to curl via a stdin config (-K -), never on the command line,
#   so it can't appear in the process listing.
# - Temp restore target is always cleaned up (trap), so a failed drill never leaves a
#   decrypted DB copy on disk.

R2_ENV=/root/.openclaw/.r2.env
OPS_DB=/root/.openclaw/ops.db
LOG=/root/.openclaw/logs/failsafe-drill.log
SNAP_PATH=/root/.openclaw/backups/r2-staging/ops.db.snapshot
ENV_FILE=/root/openclaw/.env   # compose-dir .env (mode 600) — holds TELEGRAM_* (same as r2-backup-nightly.sh)
TOLERANCE_PCT=5
RESTIC_TIMEOUT=120

# Test-only override to prove the false-green guard: RESTIC_RESTORE_PATH_OVERRIDE
# points the restore at a bogus path so the drill MUST fail + write 'failed:' state.
SNAP_RESTORE_PATH="${RESTIC_RESTORE_PATH_OVERRIDE:-$SNAP_PATH}"

mkdir -p /root/.openclaw/logs || { echo "FATAL: cannot mkdir logs dir" >&2; exit 1; }
TMPDIR_DRILL=$(mktemp -d /tmp/failsafe-drill.XXXXXX) || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TMPDIR_DRILL"' EXIT

log() { echo "$(date -u +%FT%TZ) $*" >> "$LOG"; }

# telegram_alert: token via stdin config (-K -), never on argv. Text sanitized to a
# single line with no double-quotes so it can't break the curl config parser.
telegram_alert() {
  local text token chat
  text=$(printf '%s' "$1" | tr '\r\n"' '   ')
  token=$(grep '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2)
  chat=$(grep '^TELEGRAM_CHAT_ID=' "$ENV_FILE" 2>/dev/null | cut -d= -f2)
  if [ -z "${token:-}" ] || [ -z "${chat:-}" ]; then
    log "alert skipped: no telegram creds in $ENV_FILE"; return 0
  fi
  printf 'url = "https://api.telegram.org/bot%s/sendMessage"\ndata-urlencode = "chat_id=%s"\ndata-urlencode = "text=%s"\n' \
    "$token" "$chat" "$text" | curl -sS --max-time 20 -K - >/dev/null 2>&1 || true
}

# kv_write: parameterized + checked. Returns nonzero on any failure. busy_timeout so
# a locked DB waits rather than failing spuriously.
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

fail() {
  # Teaching error shape: WHAT / HISTORY / NOT-TRIED / WHAT-WORKED
  local what="$1"
  local ts; ts=$(date -u +%FT%TZ)
  log "FAIL: $what"
  # best-effort failed-state write; if it fails we still alert + exit nonzero below
  if ! kv_write 'failsafe-drill-state' "failed: $what $ts"; then
    log "WARN: kv write of failed-state ALSO failed — kv may hold stale value; alerting anyway"
  fi
  telegram_alert "failsafe restore-drill FAILED: ${what}. History: see ${LOG}. Not tried: restic unlock, manual 'restic restore latest --path ${SNAP_PATH}'. What-worked-before: clean restic lock + re-run once R2 reachable."
  exit 1
}

log "=== failsafe restore-drill start ==="

# 0) restic env
[ -f "$R2_ENV" ] || fail "no $R2_ENV (cannot reach R2 without RESTIC_REPOSITORY/password/creds)"
set -a; . "$R2_ENV" >/dev/null 2>&1; set +a

# 1) restore the latest ops.db.snapshot to the temp target
timeout "$RESTIC_TIMEOUT" restic restore latest --path "$SNAP_RESTORE_PATH" --target "$TMPDIR_DRILL" >> "$LOG" 2>&1 \
  || fail "restic restore latest --path $SNAP_RESTORE_PATH (timeout ${RESTIC_TIMEOUT}s or R2 error — no snapshot for this path?)"

RESTORED="$TMPDIR_DRILL$SNAP_PATH"
[ -f "$RESTORED" ] || fail "restore ran but $RESTORED missing (snapshot path mismatch — verify 'restic snapshots' paths; restored path was $SNAP_RESTORE_PATH)"

# 2) SQLite integrity of the restored copy
integ=$(sqlite3 -cmd ".timeout 5000" "$RESTORED" "PRAGMA integrity_check;" 2>&1)
[ "$integ" = "ok" ] || fail "PRAGMA integrity_check on restored ops.db = '$integ' (restored backup is corrupt)"

# 3) schema drift: schema DDL hash + table count must MATCH live (catches wrong-era or
#    truncated restore). fk_check on restored must be no WORSE than live (live may hold
#    a known pre-existing violation; we only reject NEW structural breakage).
#    WHY a DDL hash, NOT `PRAGMA schema_version`: the R2 backup is a sqlite `.backup`
#    copy, and the backup API resets the DESTINATION schema cookie to 1 regardless of
#    the source (verified: snapshot=1 vs live=346 on an identical schema). So
#    schema_version would false-FAIL every drill. The sorted sqlite_master DDL hash is
#    backup-stable and is the true "same schema?" signal (this is schema, not data —
#    not the content-hash gold-plating we deliberately avoid).
snap_schemahash=$(sqlite3 "$RESTORED" "SELECT type,name,sql FROM sqlite_master ORDER BY type,name;" 2>/dev/null | sha256sum | cut -d' ' -f1)
live_schemahash=$(sqlite3 -readonly -cmd ".timeout 5000" "$OPS_DB" "SELECT type,name,sql FROM sqlite_master ORDER BY type,name;" 2>/dev/null | sha256sum | cut -d' ' -f1)
snap_tblcount=$(sqlite3 "$RESTORED" "SELECT count(*) FROM sqlite_master WHERE type='table';" 2>/dev/null)
live_tblcount=$(sqlite3 -readonly -cmd ".timeout 5000" "$OPS_DB" "SELECT count(*) FROM sqlite_master WHERE type='table';" 2>/dev/null)
snap_fkviol=$(sqlite3 "$RESTORED" "PRAGMA foreign_key_check;" 2>/dev/null | wc -l)
live_fkviol=$(sqlite3 -readonly -cmd ".timeout 5000" "$OPS_DB" "PRAGMA foreign_key_check;" 2>/dev/null | wc -l)

for v in "$snap_tblcount" "$live_tblcount"; do
  case "$v" in ''|*[!0-9]*) fail "table-count query returned non-number (snap_tblcount='$snap_tblcount' live_tblcount='$live_tblcount')";; esac
done
[ -n "$snap_schemahash" ] && [ -n "$live_schemahash" ] || fail "schema hash query returned empty (snap='$snap_schemahash' live='$live_schemahash')"
[ "$snap_schemahash" = "$live_schemahash" ] || fail "schema DDL drift: restored hash=$snap_schemahash live hash=$live_schemahash (backup predates a schema migration, or restore is structurally wrong — re-run drill after next nightly backup; if persistent, the backup is stale)"
[ "$snap_tblcount" = "$live_tblcount" ] || fail "table count drift: restored=$snap_tblcount live=$live_tblcount (restore is missing/extra tables)"
[ "$snap_fkviol" -le "$live_fkviol" ] || fail "foreign_key_check worse on restore: restored=$snap_fkviol violations vs live=$live_fkviol (restore introduced referential breakage)"

# 4) counts of TWO critical tables: restored snapshot vs live, within tolerance
snap_nodes=$(sqlite3 "$RESTORED" "SELECT count(*) FROM mem_nodes;" 2>/dev/null)
snap_edges=$(sqlite3 "$RESTORED" "SELECT count(*) FROM mem_edges;" 2>/dev/null)
snap_tasks=$(sqlite3 "$RESTORED" "SELECT count(*) FROM tasks;" 2>/dev/null)
live_nodes=$(sqlite3 -readonly -cmd ".timeout 5000" "$OPS_DB" "SELECT count(*) FROM mem_nodes;" 2>/dev/null)
live_edges=$(sqlite3 -readonly -cmd ".timeout 5000" "$OPS_DB" "SELECT count(*) FROM mem_edges;" 2>/dev/null)
live_tasks=$(sqlite3 -readonly -cmd ".timeout 5000" "$OPS_DB" "SELECT count(*) FROM tasks;" 2>/dev/null)

for v in "$snap_nodes" "$snap_edges" "$snap_tasks" "$live_nodes" "$live_edges" "$live_tasks"; do
  case "$v" in ''|*[!0-9]*) fail "count query returned non-number (snap n/e/t='$snap_nodes/$snap_edges/$snap_tasks' live n/e/t='$live_nodes/$live_edges/$live_tasks')";; esac
done

# Within-tolerance check via python (avoids bash float math)
verdict=$(python3 - "$snap_nodes" "$live_nodes" "$snap_edges" "$live_edges" "$snap_tasks" "$live_tasks" "$TOLERANCE_PCT" <<'PY'
import sys
sn, ln, se, le, st, lt, tol = map(int, sys.argv[1:8])
def drift(a, b):
    return abs(a - b) / max(b, 1) * 100.0
dn, de, dt = drift(sn, ln), drift(se, le), drift(st, lt)
ok = dn <= tol and de <= tol and dt <= tol
print(f"{'PASS' if ok else 'FAIL'} nodes_drift={dn:.2f}% edges_drift={de:.2f}% tasks_drift={dt:.2f}%")
PY
)

log "counts snapshot nodes=$snap_nodes edges=$snap_edges tasks=$snap_tasks | live nodes=$live_nodes edges=$live_edges tasks=$live_tasks | schema=ok tables=$snap_tblcount fkviol=$snap_fkviol | $verdict"

case "$verdict" in
  PASS*)
    ts=$(date -u +%FT%TZ)
    # CHECKED success write — if kv can't persist the PASS, we refuse to report success.
    kv_write 'failsafe-drill-state' "ok $ts nodes=$snap_nodes edges=$snap_edges tasks=$snap_tasks" \
      || fail "kv write of PASS state failed — refusing to report success on an unpersisted drill result (kv may hold stale value)"
    log "=== failsafe restore-drill OK ($verdict; integrity=ok schema=ok tables=$snap_tblcount fkviol=$snap_fkviol) ==="
    echo "DRILL PASS: integrity=ok schema=ok tables=$snap_tblcount fkviol=$snap_fkviol snapshot nodes=$snap_nodes edges=$snap_edges tasks=$snap_tasks vs live nodes=$live_nodes edges=$live_edges tasks=$live_tasks ($verdict)"
    ;;
  *)
    fail "count drift over ${TOLERANCE_PCT}% ($verdict; snapshot nodes=$snap_nodes edges=$snap_edges tasks=$snap_tasks vs live nodes=$live_nodes edges=$live_edges tasks=$live_tasks)"
    ;;
esac
