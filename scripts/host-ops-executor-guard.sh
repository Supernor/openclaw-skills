#!/usr/bin/env bash
# =====================================================================================
# INTENT: systemd ExecStartPre guard for the host-ops executor — make a broken edit
#         self-heal instead of crash-looping. Runs BEFORE every start of openclaw-host-ops.
# =====================================================================================
#
# WHY (cold-context): on 2026-06-03 an auto-fix agent left a tab/space mix in
# host-ops-executor.py; Python could not parse it, the service exited in ~138ms, and a
# healer restarted it every ~5 min ALL NIGHT — host ops dead until a human looked. This
# guard validates the executor source first; if it is broken it restores the last known-good
# copy, alerts Robert (gateway-independent Telegram, like stability-monitor.sh), records a
# signal, and lets systemd start the now-good file. It only FAILS the start (exit 1) when the
# source is broken AND there is no good backup to restore — i.e. when a human is truly needed,
# loud beats a silent loop. Chart: issue-executor-autoheal-self-edit-crashloop-20260603.
#
# Exit codes: 0 = source is good (original or restored) -> let ExecStart run.
#             1 = broken and unrecoverable -> systemd keeps the service failed + Robert alerted.

EXEC=/root/.openclaw/scripts/host-ops-executor.py
LASTGOOD=/root/.openclaw/scripts/.host-ops-executor.lastgood
VALIDATOR=/root/.openclaw/scripts/validate-python.py
SCARS=/root/.openclaw/scripts/scars.py
OPS_DB=/root/.openclaw/ops.db
LOG=/root/.openclaw/logs/host-ops-executor-guard.log
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TELEGRAM_TARGET=${TELEGRAM_TARGET:-8561305605}

log() { echo "[$TS] $*" >> "$LOG"; }

telegram_direct() {
  # Bypasses the gateway entirely (works when the gateway/executor are down).
  local MSG="$1" TOKEN
  if [ -n "$GUARD_DRY_RUN" ]; then log "DRY-RUN alert: $MSG"; return 0; fi
  TOKEN=$(grep '^TELEGRAM_BOT_TOKEN_ROBERT=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
  [ -z "$TOKEN" ] && TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
  [ -z "$TOKEN" ] && { log "telegram_direct: no token found"; return 1; }
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_TARGET}" -d text="${MSG}" >/dev/null 2>&1 \
    || log "telegram_direct: ERROR sending alert (curl failed)"
}

set_signal() {
  # host:executor_guard — visible on the Bridge Host panel/MOTD. ok|warn|critical.
  local status="$1" sev="$2" value="$3" message="$4"
  sqlite3 "$OPS_DB" "INSERT INTO signal_status (key,status,severity,source,value,message,updated_at,stale_after)
    VALUES ('host:executor_guard','$status','$sev','host-ops-executor-guard.sh',
      '$(printf '%s' "$value" | sed "s/'/''/g")','$(printf '%s' "$message" | sed "s/'/''/g")',
      strftime('%Y-%m-%dT%H:%M:%SZ','now'),93600)
    ON CONFLICT(key) DO UPDATE SET status=excluded.status,severity=excluded.severity,
      source=excluded.source,value=excluded.value,message=excluded.message,
      updated_at=excluded.updated_at,stale_after=excluded.stale_after;" 2>>"$LOG"
}

# --- 1. Will it START? Use --compile-only: only a parse failure (what systemd actually hits)
#        triggers a restore. A compiling-but-off-style edit (e.g. a stray tab that still parses)
#        is NOT reverted here — that would throw away a valid change. The snapshot cron flags style.
if python3 "$VALIDATOR" --quiet --compile-only "$EXEC" >/dev/null 2>&1; then
  set_signal ok info "source ok" "executor source compiles clean at start"
  log "source OK (compiles) — proceeding to start"
  exit 0
fi

# --- 2. Source is BROKEN — capture the teaching error --------------------------------------
ERR=$(python3 "$VALIDATOR" "$EXEC" 2>&1 | tr '\n' ' ' | cut -c1-300)
log "SOURCE BROKEN: $ERR"

# --- 3. Try to auto-restore from the last known-good copy ---------------------------------
if [ -f "$LASTGOOD" ] && python3 "$VALIDATOR" --quiet --compile-only "$LASTGOOD" >/dev/null 2>&1; then
  cp -a "$EXEC" "${EXEC}.broken-$(date -u +%Y%m%dT%H%M%SZ)" 2>>"$LOG"   # keep the broken copy for forensics
  cp -a "$LASTGOOD" "$EXEC" 2>>"$LOG"
  if python3 "$VALIDATOR" --quiet --compile-only "$EXEC" >/dev/null 2>&1; then
    log "AUTO-RECOVERED: restored last-good executor source"
    set_signal warn medium "auto-recovered" "restored last-good source after a broken edit; broken copy saved. was: $ERR"
    # The system records its OWN break: bump the executor's scar so a recurrence is counted/visible
    # (the instinct — a break that recurs is the real failure). Skipped under dry-run tests.
    [ -z "$GUARD_DRY_RUN" ] && python3 "$SCARS" bump "$EXEC" >>"$LOG" 2>&1
    telegram_direct "🛠️ Executor auto-recovered: host-ops-executor.py was broken ($ERR) — restored last-good copy and starting. Broken copy saved for review."
    exit 0
  fi
  log "RESTORE FAILED: copied last-good but it still does not validate"
fi

# --- 4. Broken AND no good backup -> fail loud (human needed) ------------------------------
set_signal critical critical "broken-unrecoverable" "executor source broken and no valid backup: $ERR"
telegram_direct "🚨 Executor WILL NOT START: host-ops-executor.py is broken ($ERR) and there is no valid backup to restore. Manual fix needed (run: python3 /root/.openclaw/scripts/validate-python.py $EXEC)."
log "UNRECOVERABLE — failing ExecStartPre so systemd does not loop silently"
exit 1
