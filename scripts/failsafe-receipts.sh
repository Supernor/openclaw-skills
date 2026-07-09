#!/bin/bash
# === INTENT ===
# Deterministic evidence collector for the Failsafe agent's weekly backup audit.
# NO LLM, NO judgment — just emits 'key: value' facts the agent judges from its
# pushed context. Never prints credentials or the restic password file contents.
set -uo pipefail

# WHY each piece:
# - The Failsafe agent (weak nemotron) judges PUSHED text only; this script is the
#   only thing that touches restic/kv/disk. Keep output tiny, literal, key:value.
# - Any probe that cannot answer emits 'key: UNAVAILABLE (<why>)' — we NEVER
#   fabricate a healthy number, because a false "backup ok" is worse than silence.
# - .r2.env holds RESTIC_REPOSITORY + RESTIC_PASSWORD_FILE + R2 creds; we source it
#   with stdout+stderr discarded so no env content can leak into the receipts that
#   get pushed into the agent prompt (prompt-injection / credential-leak guard).
# - emit() is the ONLY sink for untrusted text (kv values, log tails): it forces
#   single-line, redacts credential patterns, and caps length so no receipt line
#   can escape the key:value shape and smuggle instructions to the weak judge.
# - Runs in <60s: restic calls are timeout-bounded so a hung R2 can't stall cron.

R2_ENV=/root/.openclaw/.r2.env
LOG=/root/.openclaw/logs/r2-backup.log
DRILL_LOG=/root/.openclaw/logs/failsafe-drill.log
OPS_DB=/root/.openclaw/ops.db
BACKUPS_DIR=/root/.openclaw/backups
SNAP_PATH=/root/.openclaw/backups/r2-staging/ops.db.snapshot
TREE_PATH=/root/.openclaw
HOSTN=$(hostname)
TIER_GB=10
RESTIC_TIMEOUT=40

# --- restic env (silent, stdout+stderr discarded): missing -> probes UNAVAILABLE
RESTIC_READY=0
if [ -f "$R2_ENV" ]; then
  set -a; . "$R2_ENV" >/dev/null 2>&1; set +a
  RESTIC_READY=1
fi

# emit(): single sink for untrusted values. Collapse whitespace, redact any
# credential-shaped token, cap to 300 chars. Numeric/controlled lines that python
# prints directly bypass this on purpose (no injection surface there).
emit() {
  local k="$1" v="$2"
  v=$(printf '%s' "$v" | tr '\r\n\t' '   ')
  v=$(printf '%s' "$v" | sed -E \
    -e 's#(https?://)[^/@ ]*:[^/@ ]*@#\1[creds-redacted]@#g' \
    -e 's#(RESTIC_PASSWORD[A-Z_]*|RESTIC_REPOSITORY|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|TELEGRAM_BOT_TOKEN|password|passwd|secret|token|apikey|api_key)([=:][[:space:]]*)[^[:space:]]*#\1\2[redacted]#Ig')
  v=$(printf '%s' "$v" | cut -c1-300)
  printf '%s: %s\n' "$k" "$v"
}

# 1) r2-backup-state kv value + deterministic age
val=$(sqlite3 -readonly -cmd ".timeout 5000" "$OPS_DB" "SELECT value FROM kv WHERE key='r2-backup-state';" 2>/dev/null)
if [ -z "$val" ]; then
  emit "r2-backup-state" "UNAVAILABLE (no kv row 'r2-backup-state')"
  emit "r2-backup-age-days" "UNAVAILABLE (no kv row)"
else
  emit "r2-backup-state" "$val"
  python3 -W ignore - "$val" <<'PY'
import sys, re, datetime
v = sys.argv[1]
m = re.search(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})', v)
if not m:
    print("r2-backup-age-days: UNAVAILABLE (no timestamp in kv value)"); sys.exit(0)
try:
    dt = datetime.datetime.fromisoformat(m.group(1))
    age = (datetime.datetime.utcnow() - dt).total_seconds() / 86400.0
    if age < 0:
        print(f"r2-backup-age-days: UNAVAILABLE (negative/future age {age:.2f})")
    else:
        print(f"r2-backup-age-days: {age:.2f}")
except Exception as e:
    print(f"r2-backup-age-days: UNAVAILABLE (parse: {e})")
PY
fi

# 2) last 3 lines of the backup log (redacted + single-line via emit)
if [ -f "$LOG" ]; then
  n=0
  while IFS= read -r line; do
    n=$((n+1))
    emit "r2-backup-log-$n" "$line"
  done < <(tail -n 3 "$LOG" 2>/dev/null)
  [ "$n" -eq 0 ] && emit "r2-backup-log" "UNAVAILABLE (log empty)"
else
  emit "r2-backup-log" "UNAVAILABLE (no $LOG)"
fi

# 3) restic snapshots: count + latest age BOUND to each expected path+host, so a
#    recent unrelated snapshot can't mask a broken ops.db.snapshot stream. Require
#    restic exit 0 AND parseable JSON — nonzero-with-partial-JSON is UNAVAILABLE.
if [ "$RESTIC_READY" -eq 1 ]; then
  snap_json=$(timeout "$RESTIC_TIMEOUT" restic snapshots --json 2>/dev/null); rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$snap_json" ]; then
    python3 -W ignore - "$snap_json" "$SNAP_PATH" "$TREE_PATH" "$HOSTN" <<'PY'
import sys, json, datetime
snap_json, snap_path, tree_path, host = sys.argv[1:5]
try:
    d = json.loads(snap_json)
except Exception as e:
    print(f"restic-snapshot-count: UNAVAILABLE (parse: {e})"); sys.exit(0)
print(f"restic-snapshot-count: {len(d)}")
now = datetime.datetime.utcnow()
def latest_age(target):
    best = None
    for s in d:
        if host and s.get('hostname') and s.get('hostname') != host:
            continue
        if target in (s.get('paths') or []):
            t = s.get('time', '')
            if t and (best is None or t > best):
                best = t
    if best is None:
        return None
    try:
        dt = datetime.datetime.fromisoformat(best.split('.')[0].rstrip('Z'))
        return (now - dt).total_seconds() / 86400.0
    except Exception:
        return 'parse'
for label, target in (("restic-opsdb-snapshot-age-days", snap_path),
                      ("restic-openclaw-snapshot-age-days", tree_path)):
    a = latest_age(target)
    if a is None:
        print(f"{label}: UNAVAILABLE (no snapshot for path {target} on host {host})")
    elif a == 'parse':
        print(f"{label}: UNAVAILABLE (snapshot time parse failed)")
    elif a < 0:
        print(f"{label}: UNAVAILABLE (negative/future age {a:.2f})")
    else:
        print(f"{label}: {a:.2f}")
PY
  else
    emit "restic-snapshot-count" "UNAVAILABLE (restic snapshots exit=$rc/timeout ${RESTIC_TIMEOUT}s)"
    emit "restic-opsdb-snapshot-age-days" "UNAVAILABLE (restic snapshots exit=$rc)"
    emit "restic-openclaw-snapshot-age-days" "UNAVAILABLE (restic snapshots exit=$rc)"
  fi

  stats_json=$(timeout "$RESTIC_TIMEOUT" restic stats --mode raw-data --json 2>/dev/null); rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$stats_json" ]; then
    python3 -W ignore - "$stats_json" "$TIER_GB" <<'PY'
import sys, json
try:
    d = json.loads(sys.argv[1]); tier = float(sys.argv[2])
    gb = d.get('total_size', 0) / (1024**3)
    print(f"restic-repo-raw-size-gb: {gb:.2f}")
    print(f"restic-tier-line-gb: {tier:.0f}")
    print(f"restic-tier-headroom-gb: {tier-gb:.2f}")
except Exception as e:
    print(f"restic-repo-raw-size-gb: UNAVAILABLE (parse: {e})")
PY
  else
    emit "restic-repo-raw-size-gb" "UNAVAILABLE (restic stats exit=$rc/timeout ${RESTIC_TIMEOUT}s)"
    emit "restic-tier-line-gb" "$TIER_GB"
  fi
else
  emit "restic-snapshot-count" "UNAVAILABLE (no $R2_ENV)"
  emit "restic-opsdb-snapshot-age-days" "UNAVAILABLE (no $R2_ENV)"
  emit "restic-openclaw-snapshot-age-days" "UNAVAILABLE (no $R2_ENV)"
  emit "restic-repo-raw-size-gb" "UNAVAILABLE (no $R2_ENV)"
  emit "restic-tier-line-gb" "$TIER_GB"
fi

# 4) restore drill: kv state + age + an INDEPENDENT signal (drill log tail), so a
#    failed drill whose kv write also failed still shows a failure in the receipts.
drill=$(sqlite3 -readonly -cmd ".timeout 5000" "$OPS_DB" "SELECT value FROM kv WHERE key='failsafe-drill-state';" 2>/dev/null)
if [ -z "$drill" ]; then
  emit "failsafe-drill-state" "UNAVAILABLE (no kv row 'failsafe-drill-state' — no drill has ever run)"
  emit "failsafe-drill-age-days" "UNAVAILABLE (never run)"
else
  emit "failsafe-drill-state" "$drill"
  # value shape: 'ok <iso-ts> nodes=N edges=M tasks=T' or 'failed: <why> <iso-ts>'
  python3 -W ignore - "$drill" <<'PY'
import sys, re, datetime
v = sys.argv[1]
m = re.search(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})', v)
if not m:
    print("failsafe-drill-age-days: UNAVAILABLE (no timestamp in kv value)"); sys.exit(0)
try:
    dt = datetime.datetime.fromisoformat(m.group(1))
    age = (datetime.datetime.utcnow() - dt).total_seconds() / 86400.0
    if age < 0:
        print(f"failsafe-drill-age-days: UNAVAILABLE (negative/future age {age:.2f})")
    else:
        print(f"failsafe-drill-age-days: {age:.2f}")
except Exception as e:
    print(f"failsafe-drill-age-days: UNAVAILABLE (parse: {e})")
PY
fi

# independent drill signal: last 2 log lines (redacted single-line via emit)
if [ -f "$DRILL_LOG" ]; then
  n=0
  while IFS= read -r line; do
    n=$((n+1))
    emit "failsafe-drill-log-$n" "$line"
  done < <(tail -n 2 "$DRILL_LOG" 2>/dev/null)
  [ "$n" -eq 0 ] && emit "failsafe-drill-log" "UNAVAILABLE (drill log empty)"
else
  emit "failsafe-drill-log" "UNAVAILABLE (no $DRILL_LOG — drill never ran)"
fi

# 5) local backups/ dir size + newest ARTIFACT age. Filter to real backup artifacts
#    (ops-*.db* + *.snapshot) and exclude r2-staging: a fresh staging temp file must
#    never make the local fallback look current when the real artifacts are stale.
if [ -d "$BACKUPS_DIR" ]; then
  sz=$(du -sh "$BACKUPS_DIR" 2>/dev/null | cut -f1)
  emit "local-backups-size" "${sz:-UNAVAILABLE (du failed)}"
  newest=$(find "$BACKUPS_DIR" -type f \( -name 'ops-*.db*' -o -name '*.snapshot' \) \
    -not -path '*/r2-staging/*' -printf '%T@\n' 2>/dev/null | sort -nr | head -n1)
  if [ -n "$newest" ]; then
    python3 -W ignore - "$newest" <<'PY'
import sys, time
age = (time.time() - float(sys.argv[1])) / 86400.0
if age < 0:
    print(f"local-backups-newest-artifact-age-days: UNAVAILABLE (negative/future {age:.2f})")
else:
    print(f"local-backups-newest-artifact-age-days: {age:.2f}")
PY
  else
    emit "local-backups-newest-artifact-age-days" "UNAVAILABLE (no ops-*.db*/*.snapshot artifacts under backups/ outside r2-staging)"
  fi
else
  emit "local-backups-size" "UNAVAILABLE (no $BACKUPS_DIR)"
  emit "local-backups-newest-artifact-age-days" "UNAVAILABLE (no $BACKUPS_DIR)"
fi

# summary: the four decision values pre-computed for the weak judge (learned
# 2026-07-08: nemotron misreads scattered keys; give it one line to threshold).
# Re-derives from the same kv/log sources; any piece unparseable -> UNAVAILABLE.
python3 -W ignore - "$OPS_DB" "$DRILL_LOG" <<'PY'
import sys, sqlite3, time, re
db, drill_log = sys.argv[1], sys.argv[2]
def kv(key):
    try:
        c = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=6)
        c.execute("PRAGMA busy_timeout=5000")
        r = c.execute("SELECT value FROM kv WHERE key=?", (key,)).fetchone()
        c.close(); return r[0] if r else None
    except Exception: return None
def age_days(val):
    if not val: return None
    m = re.search(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)", val)
    if not m: return None
    a = (time.time() - time.mktime(time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%SZ")) + time.timezone) / 86400.0
    return None if a < 0 else a
bstate, dstate = kv("r2-backup-state"), kv("failsafe-drill-state")
ba, da = age_days(bstate), age_days(dstate)
bok = "ok" if (bstate or "").startswith("ok") else "failed" if bstate else "UNAVAILABLE"
dok = "PASS" if (dstate or "").startswith("ok") else "failed" if dstate else "UNAVAILABLE"
fmt = lambda x: f"{x:.2f}" if x is not None else "UNAVAILABLE"
print(f"summary: backup={bok} backup-age-days={fmt(ba)} drill={dok} drill-age-days={fmt(da)}")
PY

emit "receipts-generated-utc" "$(date -u +%FT%TZ)"
