#!/usr/bin/env bash
# codex-auth-precheck.sh — Proactive Codex auth refresh.
#
# WHEN TO USE: Runs daily via cron at 06:00 UTC. Safe to run manually anytime.
# WHAT IT DOES: Checks JWT expiry on host tokens. If <48h remain, triggers fix-codex-auth.sh.
# IF IT FAILS: Check /root/.openclaw/logs/codex-auth-precheck.log for outcome codes.
#   Outcome codes: ok | refreshed | parse_fail_refresh
#   DO THIS: Run fix-codex-auth.sh --check manually to see raw status.
#
# Cron: 0 6 * * * /root/.openclaw/scripts/codex-auth-precheck.sh
# Lock: flock prevents overlapping runs (cron + manual + auth-watcher).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCK_FILE="/tmp/codex-auth-precheck.lock"
LOG="/root/.openclaw/logs/codex-auth-precheck.log"
AUTH_FILE="$HOME/.codex/auth.json"
THRESHOLD_HOURS=48

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$LOG"; }

# --- flock: prevent overlapping runs ---
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "OUTCOME=skipped_locked — another precheck is already running"
    exit 0
fi

# --- Parse remaining hours (fallback-safe) ---
get_remaining_hours() {
    # Primary: run fix-codex-auth.sh --check and parse output
    local status_output
    status_output=$("$SCRIPT_DIR/fix-codex-auth.sh" --check 2>&1) || true

    # Try grep -oP first (GNU grep)
    local hours
    hours=$(echo "$status_output" | grep -oP '\d+(?=h remaining)' 2>/dev/null) || true

    if [ -n "$hours" ] && [ "$hours" -eq "$hours" ] 2>/dev/null; then
        echo "$hours"
        return 0
    fi

    # Fallback: parse JWT directly if --check output format changed
    if [ -f "$AUTH_FILE" ]; then
        hours=$(python3 -c "
import json, base64, time, sys
try:
    with open('$AUTH_FILE') as f:
        auth = json.load(f)
    token = auth.get('tokens', auth).get('access_token', '')
    if not token or '.' not in token:
        print(''); sys.exit(0)
    payload = token.split('.')[1]
    payload += '=' * (4 - len(payload) % 4)
    exp = json.loads(base64.urlsafe_b64decode(payload)).get('exp', 0)
    remaining_h = int((exp - time.time()) / 3600)
    print(remaining_h)
except Exception:
    print('')
" 2>/dev/null) || true

        if [ -n "$hours" ] && [ "$hours" -eq "$hours" ] 2>/dev/null; then
            echo "$hours"
            return 0
        fi
    fi

    # Both parsing methods failed
    echo ""
    return 1
}

# --- Main logic ---
REMAINING=$(get_remaining_hours)

if [ -z "$REMAINING" ]; then
    log "OUTCOME=parse_fail_refresh — could not determine expiry, triggering fix as safety measure"
    "$SCRIPT_DIR/fix-codex-auth.sh" 2>&1 | tee -a "$LOG"
    exit 0
fi

if [ "$REMAINING" -lt "$THRESHOLD_HOURS" ]; then
    log "OUTCOME=refreshed — ${REMAINING}h < ${THRESHOLD_HOURS}h threshold, triggering proactive refresh"
    "$SCRIPT_DIR/fix-codex-auth.sh" 2>&1 | tee -a "$LOG"
else
    log "OUTCOME=ok — ${REMAINING}h remaining (threshold: ${THRESHOLD_HOURS}h)"
fi
