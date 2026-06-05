#!/usr/bin/env bash
# =====================================================================================
# INTENT: systemd ExecStartPre guard for the host-ops executor — make a broken edit
#         self-heal instead of crash-looping. Runs BEFORE every start of openclaw-host-ops.
# =====================================================================================
#
# WHY (cold-context): on 2026-06-03 an auto-fix agent left a tab/space mix in
# host-ops-executor.py; Python could not parse it, the service exited in ~138ms, and a
# healer restarted it every ~5 min ALL NIGHT — host ops dead until a human looked. This
# guard validates the guarded sources first; if one is broken it restores the last known-good
# copy, alerts Robert (gateway-independent Telegram, like stability-monitor.sh), records a
# signal, and lets systemd start the now-good files. It only FAILS the start (exit 1) when a
# source is broken AND there is no good backup to restore — i.e. when a human is truly needed,
# loud beats a silent loop. Chart: issue-executor-autoheal-self-edit-crashloop-20260603.
#
# 2026-06-04: GENERALIZED to cover BOTH host-ops-executor.py AND engine.py. engine.py is
# imported in-process by the executor (import engine), so a broken engine.py edit crash-loops
# the executor just as a broken entry file would — but the old guard only validated the entry
# file (blind spot #7b). Now each guarded file has its own .lastgood and is validated/restored
# independently. Chart: fix-codex-routable-timestamp-format-20260603 (the edit that exposed it).
#
# Exit codes: 0 = all guarded sources good (original or restored) -> let ExecStart run.
#             1 = a source is broken and unrecoverable -> service stays failed + Robert alerted.

VALIDATOR=/root/.openclaw/scripts/validate-python.py
SCARS=/root/.openclaw/scripts/scars.py
OPS_DB=/root/.openclaw/ops.db
LOG=/root/.openclaw/logs/host-ops-executor-guard.log
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TELEGRAM_TARGET=${TELEGRAM_TARGET:-8561305605}

# Guarded files: "label|source|lastgood". Each is validated and, if broken, restored from its
# own last-good snapshot (maintained by executor-snapshot-lastgood.sh */15).
GUARDED=(
  "host-ops-executor.py|/root/.openclaw/scripts/host-ops-executor.py|/root/.openclaw/scripts/.host-ops-executor.lastgood"
  "engine.py|/root/.openclaw/scripts/engine.py|/root/.openclaw/scripts/.engine.lastgood"
)

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

# guard_one LABEL SOURCE LASTGOOD — validate one guarded file; restore from last-good if broken.
# Prints exactly one status token to stdout: OK | RECOVERED | UNRECOVERABLE:<err>
# (Runs in a command-substitution subshell; only this stdout token is consumed by the caller.
#  Uses --compile-only — only a genuine PARSE failure, which is what systemd actually hits, triggers
#  a restore; a compiling-but-styled edit is left alone so a valid change is never thrown away.)
guard_one() {
  local label="$1" src="$2" lg="$3" err
  if python3 "$VALIDATOR" --quiet --compile-only "$src" >/dev/null 2>&1; then
    echo "OK"; return 0
  fi
  err=$(python3 "$VALIDATOR" "$src" 2>&1 | tr '\n' ' ' | cut -c1-300)
  log "SOURCE BROKEN ($label): $err"
  if [ -f "$lg" ] && python3 "$VALIDATOR" --quiet --compile-only "$lg" >/dev/null 2>&1; then
    cp -a "$src" "${src}.broken-$(date -u +%Y%m%dT%H%M%SZ)" 2>>"$LOG"   # keep broken copy for forensics
    cp -a "$lg" "$src" 2>>"$LOG"
    if python3 "$VALIDATOR" --quiet --compile-only "$src" >/dev/null 2>&1; then
      log "AUTO-RECOVERED ($label): restored last-good source"
      # The system records its OWN break: bump the file's scar so a recurrence is counted/visible.
      [ -z "$GUARD_DRY_RUN" ] && python3 "$SCARS" bump "$src" >>"$LOG" 2>&1
      telegram_direct "🛠️ Executor auto-recovered: $label was broken ($err) — restored last-good copy and starting. Broken copy saved for review."
      echo "RECOVERED"; return 0
    fi
    log "RESTORE FAILED ($label): copied last-good but it still does not validate"
  fi
  echo "UNRECOVERABLE:$err"; return 1
}

# --- Validate every guarded source; track the worst outcome -------------------------------
WORST=ok
MSG="all guarded sources compile clean"
for entry in "${GUARDED[@]}"; do
  IFS='|' read -r label src lg <<< "$entry"
  res=$(guard_one "$label" "$src" "$lg")
  case "$res" in
    OK) ;;
    RECOVERED) [ "$WORST" = ok ] && { WORST=warn; MSG="auto-recovered $label from last-good after a broken edit"; } ;;
    UNRECOVERABLE:*) WORST=critical; MSG="$label broken and no valid backup: ${res#UNRECOVERABLE:}" ;;
  esac
done

case "$WORST" in
  ok)
    set_signal ok info "source ok" "$MSG"
    log "all guarded sources OK (compile) — proceeding to start"
    exit 0 ;;
  warn)
    set_signal warn medium "auto-recovered" "$MSG"
    exit 0 ;;
  critical)
    set_signal critical critical "broken-unrecoverable" "$MSG"
    telegram_direct "🚨 Executor WILL NOT START: $MSG. Manual fix needed (run: python3 $VALIDATOR <file>)."
    log "UNRECOVERABLE — failing ExecStartPre so systemd does not loop silently"
    exit 1 ;;
esac
