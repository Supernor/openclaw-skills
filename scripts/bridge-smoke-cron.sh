#!/usr/bin/env bash
# === INTENT: bridge-smoke-cron.sh — run the Layer-1 smoke suite + alert ONLY on label change ===
# === Mirrors api-health-probe.sh: the SCRIPT owns state-change Telegram alerting; cron-wrapper.sh ===
# === (in the crontab line) records the cron_outcomes row + RESULT_LABEL. No 15-min spam. ===
# === telegram_direct is GATEWAY-INDEPENDENT (reads token straight from .env) — it must keep working ===
# === when the very thing being watched (the Bridge / gateway) is down. ===
#
# APPLY TO:  /root/.openclaw/scripts/bridge-smoke-cron.sh   (lives with the other cron scripts;
#            it uses cron-wrapper.sh + .env + telegram-resolve, all rooted in /root/.openclaw + /root/openclaw)
#
# Invoked by crontab as (see artifact3-crontab.line):
#   */15 * * * * flock -n /tmp/cron-bridge-smoke.lock /root/.openclaw/scripts/cron-wrapper.sh \
#       bridge-smoke /root/.openclaw/scripts/bridge-smoke-cron.sh >> /root/.openclaw/logs/bridge-smoke.log 2>&1
#   - flock (crontab level, system convention) stops 15-min runs from stacking.
#   - cron-wrapper.sh records job_name='bridge-smoke' + the RESULT_LABEL this script re-emits.
#   - THIS script runs run-all.sh (Layer 1 only) and alerts on transitions.
#
# Layer-1 contract: run-all.sh is GET + static reads ONLY; it never auto-runs side-effecting layers.

set -uo pipefail

RUN_ALL="/root/bridge-dev/tests/run-all.sh"
ENV_FILE="/root/openclaw/.env"
STATE_FILE="/root/.openclaw/.bridge-smoke-state.json"

# --- gateway-independent Telegram (same pattern as api-health-probe.sh / stability-monitor.sh) ---
read_env_token() { grep "^${1}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d "'" | tr -d '"'; }
telegram_direct() {
  local MSG="$1" TOKEN CHAT_ID
  TOKEN=$(read_env_token "TELEGRAM_BOT_TOKEN_ROBERT")
  [ -z "$TOKEN" ] && TOKEN=$(read_env_token "TELEGRAM_BOT_TOKEN")
  [ -z "$TOKEN" ] && return 1
  CHAT_ID=$(telegram-resolve robert 2>/dev/null || echo "8561305605")
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" -d text="${MSG}" >/dev/null 2>&1
}

# --- run the suite; re-emit its output so cron-wrapper sees RESULT_LABEL and the log keeps it all ---
OUT="$(bash "$RUN_ALL" --trigger cron 2>&1)"; RC=$?
printf '%s\n' "$OUT"

LABEL="$(printf '%s\n' "$OUT" | grep -m1 '^RESULT_LABEL:' | sed 's/^RESULT_LABEL: *//' | tr -d '[:space:]')"
[ -z "$LABEL" ] && LABEL="error"

# --- state-change-only alert: compare to .bridge-smoke-state.json, telegram on transition only ---
PREV="unknown"
if [ -f "$STATE_FILE" ]; then
  PREV="$(python3 -c "import json;print(json.load(open('$STATE_FILE')).get('label','unknown'))" 2>/dev/null || echo unknown)"
fi

if [ "$LABEL" != "$PREV" ]; then
  case "$LABEL" in
    healthy)
      # Announce RECOVERY only — never page on the first-ever/cold-start healthy.
      [ "$PREV" != "unknown" ] && telegram_direct "Bridge smoke RECOVERED: ${PREV} -> healthy (all GET surfaces + UI wiring green)."
      ;;
    issues_found)
      telegram_direct "Bridge smoke: ${PREV} -> issues_found. A GET surface or UI wiring point broke. Open Bridge -> Smoke (section-bridge-smoke) for the failing rows."
      ;;
    error)
      telegram_direct "Bridge smoke: ${PREV} -> error. A smoke script failed to RUN — Layer-1 self-check is BLIND until fixed. See /root/.openclaw/logs/bridge-smoke.log."
      ;;
    *)
      telegram_direct "Bridge smoke: ${PREV} -> ${LABEL}."
      ;;
  esac
  printf '{"label":"%s","prev":"%s","ts":"%s"}\n' \
    "$LABEL" "$PREV" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_FILE"
fi

# Preserve run-all.sh's exit code so cron-wrapper records the true outcome.
exit "$RC"
