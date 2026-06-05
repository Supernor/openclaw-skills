#!/usr/bin/env bash
# =====================================================================================
# INTENT: (1) proactively flag a non-compiling guarded source within 15 min, and
#         (2) keep each <file>.lastgood = the last PROVEN-HEALTHY, clean source
#             (the start-guard host-ops-executor-guard.sh restores these on a broken edit).
# =====================================================================================
#
# ORDER MATTERS: source-compilability is checked FIRST, independent of uptime — a broken edit is
# worth flagging even on a freshly-restarted service. The SNAPSHOT (-> lastgood) is gated on
# >= MIN_HEALTHY_SECS of continuous EXECUTOR uptime (never snapshot a version that compiles but
# crashes at runtime; a crash-looping version never accumulates that uptime) AND a full style check
# (so lastgood stays pristine). Cron: */15.
# See issue-executor-autoheal-self-edit-crashloop-20260603 + host-ops-executor-guard.sh.
#
# 2026-06-04: GENERALIZED to cover engine.py too (imported in-process by the executor). The same
# executor-uptime gate is a valid health proxy for engine.py — a broken engine.py would crash the
# executor's `import engine` at startup, so sustained uptime implies engine.py imports clean.

VALIDATOR=/root/.openclaw/scripts/validate-python.py
OPS_DB=/root/.openclaw/ops.db
LOG=/root/.openclaw/logs/host-ops-executor-guard.log
MIN_HEALTHY_SECS=600
TELEGRAM_TARGET=${TELEGRAM_TARGET:-8561305605}

# Guarded files: "label|source|lastgood" — must match host-ops-executor-guard.sh.
GUARDED=(
  "host-ops-executor.py|/root/.openclaw/scripts/host-ops-executor.py|/root/.openclaw/scripts/.host-ops-executor.lastgood"
  "engine.py|/root/.openclaw/scripts/engine.py|/root/.openclaw/scripts/.engine.lastgood"
)

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] snapshot: $*" >> "$LOG"; }

telegram_direct() {
  local MSG="$1" TOKEN
  if [ -n "$GUARD_DRY_RUN" ]; then log "DRY-RUN alert: $MSG"; return 0; fi
  TOKEN=$(grep '^TELEGRAM_BOT_TOKEN_ROBERT=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
  [ -z "$TOKEN" ] && TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
  [ -z "$TOKEN" ] && { log "telegram_direct: no token found"; return 1; }
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_TARGET}" -d text="${MSG}" >/dev/null 2>&1 \
    || log "telegram_direct: ERROR sending alert (curl failed)"
}

set_guard_signal() {  # status sev value message [stale]
  local status="$1" sev="$2" value="$3" message="$4" stale="${5:-93600}"
  sqlite3 "$OPS_DB" "INSERT INTO signal_status (key,status,severity,source,value,message,updated_at,stale_after)
    VALUES ('host:executor_guard','$status','$sev','executor-snapshot-lastgood.sh',
      '$(printf '%s' "$value" | sed "s/'/''/g")','$(printf '%s' "$message" | sed "s/'/''/g")',
      strftime('%Y-%m-%dT%H:%M:%SZ','now'),'$stale')
    ON CONFLICT(key) DO UPDATE SET status=excluded.status,severity=excluded.severity,
      source=excluded.source,value=excluded.value,message=excluded.message,
      updated_at=excluded.updated_at,stale_after=excluded.stale_after;" 2>>"$LOG"
}

# --- 1. Will every guarded source COMPILE? (independent of uptime). --compile-only matches the
#        guard's restore decision: only a genuine parse failure means "the next restart breaks". ---
BROKEN_LABELS=""
BROKEN_ERR=""
for entry in "${GUARDED[@]}"; do
  IFS='|' read -r label src lg <<< "$entry"
  if ! python3 "$VALIDATOR" --quiet --compile-only "$src" >/dev/null 2>&1; then
    err=$(python3 "$VALIDATOR" "$src" 2>&1 | tr '\n' ' ' | cut -c1-200)
    log "WARNING: $label does NOT COMPILE (not snapshotting): $err"
    BROKEN_LABELS="${BROKEN_LABELS:+$BROKEN_LABELS,}$label"
    BROKEN_ERR="$label: $err"
  fi
done

if [ -n "$BROKEN_LABELS" ]; then
  PRIOR=$(sqlite3 "$OPS_DB" "SELECT value FROM signal_status WHERE key='host:executor_guard';" 2>/dev/null)
  # Running process is still fine (old code in memory); the NEXT restart would hit this and the
  # guard would auto-restore — flag it now so Robert hears within 15 min, not at 3am.
  set_guard_signal warn medium "source-broken-pending-restart" "$BROKEN_ERR" 1800
  # State-change only (op rule 6): alert on the transition INTO broken, not every */15 cycle.
  if [ "$PRIOR" != "source-broken-pending-restart" ]; then
    telegram_direct "⚠️ $BROKEN_LABELS source will NOT COMPILE but the executor is still running on old code. It auto-restores on next restart; check it: $BROKEN_ERR"
  else
    log "alert suppressed (already in source-broken state — state-change only)"
  fi
  exit 0
fi
# All guarded sources compile -> clear a prior source-broken warning back to ok
sqlite3 "$OPS_DB" "UPDATE signal_status SET status='ok',severity='info',value='source ok',
  message='all guarded sources compile',updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now'),stale_after=93600
  WHERE key='host:executor_guard' AND value='source-broken-pending-restart';" 2>>"$LOG"

# --- 2. Snapshot gate: executor active + healthy long enough -------------------------------
[ "$(systemctl is-active openclaw-host-ops)" = "active" ] || { log "skip snapshot (not active)"; exit 0; }
ACTIVE_SINCE=$(systemctl show -p ActiveEnterTimestamp --value openclaw-host-ops 2>/dev/null)
[ -z "$ACTIVE_SINCE" ] && { log "skip snapshot (no ActiveEnterTimestamp)"; exit 0; }
SINCE_EPOCH=$(date -d "$ACTIVE_SINCE" +%s 2>/dev/null) || { log "skip snapshot (cannot parse timestamp)"; exit 0; }
AGE=$(( $(date +%s) - SINCE_EPOCH ))
[ "$AGE" -ge "$MIN_HEALTHY_SECS" ] || { log "skip snapshot (healthy only ${AGE}s, need ${MIN_HEALTHY_SECS}s)"; exit 0; }

# Gate passed -> refresh each guarded file's lastgood if it is FULLY clean and has changed.
for entry in "${GUARDED[@]}"; do
  IFS='|' read -r label src lg <<< "$entry"
  # Snapshot only a FULLY clean source (compiles AND no tab/style issues) so lastgood stays pristine.
  if ! python3 "$VALIDATOR" --quiet "$src" >/dev/null 2>&1; then
    log "skip snapshot ($label compiles but fails full style check; keeping prior lastgood)"
    continue
  fi
  if [ -f "$lg" ] && cmp -s "$src" "$lg"; then
    continue  # unchanged
  fi
  # Atomic write so the guard can never read a half-written lastgood.
  cp -a "$src" "${lg}.tmp" && mv -f "${lg}.tmp" "$lg" \
    && log "refreshed lastgood for $label (executor healthy ${AGE}s, source clean)"
done
exit 0
