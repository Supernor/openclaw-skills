#!/usr/bin/env bash
# cron-alert.sh — Wrapper that runs a cron job and alerts on failure
# Usage: cron-alert.sh <job-name> <command> [args...]
# On failure: logs to ops.db incidents + sends Telegram/Discord notification
# Intent: Observable [I13]. Created: 2026-03-09.
set -o pipefail

usage() {
    echo "Usage: cron-alert.sh <job-name> <command> [args...]" >&2
    echo "       cron-alert.sh --notify-only <job-name> <exit-code> [output]" >&2
}

telegram_direct() {
    local MSG="$1"
    local TARGET="${TELEGRAM_TARGET:-}"
    local TOKEN

    if [ -z "$TARGET" ] && command -v telegram-resolve >/dev/null 2>&1; then
        TARGET=$(telegram-resolve robert 2>/dev/null || true)
    fi
    TARGET=${TARGET:-8561305605}

    TOKEN=$(grep '^TELEGRAM_BOT_TOKEN_ROBERT=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
    [ -z "$TOKEN" ] && TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
    [ -z "$TOKEN" ] && return 1

    curl -sf -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d chat_id="${TARGET}" \
        -d text="${MSG}" >/dev/null 2>&1
}

notify_failure() {
    local JOB_NAME="$1"
    local EXIT_CODE="$2"
    local OUTPUT="${3:-}"
    local TS
    local SHORT_OUTPUT
    local TELEGRAM_STATUS
    local DISCORD_STATUS

    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # Truncate output for incident description
    SHORT_OUTPUT=$(printf "%s" "$OUTPUT" | tail -5 | head -c 500)

    # Log to ops.db incidents (fallback to local file on failure)
    if ! /root/.openclaw/scripts/ops-db.py incident open "Cron failure: ${JOB_NAME}" \
        --severity medium \
        --desc "Exit code ${EXIT_CODE} at ${TS}. Output: ${SHORT_OUTPUT}" 2>/dev/null; then
        mkdir -p /root/.openclaw/logs
        echo "{\"ts\":\"${TS}\",\"source\":\"cron-alert\",\"job\":\"${JOB_NAME}\",\"exit_code\":${EXIT_CODE},\"output\":\"$(echo "$SHORT_OUTPUT" | tr '"' "'" | tr '\n' ' ')\"}" \
            >> /root/.openclaw/logs/cron-failures.jsonl
    fi

    # Write to health buffer
    mkdir -p /root/.openclaw/health
    echo "{\"ts\":\"${TS}\",\"source\":\"cron-alert\",\"job\":\"${JOB_NAME}\",\"exit_code\":${EXIT_CODE}}" \
        >> /root/.openclaw/health/buffer.jsonl 2>/dev/null || true

    if telegram_direct "Cron FAILED: ${JOB_NAME} (exit ${EXIT_CODE}) at ${TS}
${SHORT_OUTPUT}"; then
        TELEGRAM_STATUS="sent"
    else
        TELEGRAM_STATUS="failed"
    fi

    # Send Discord notification via gateway
    docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway \
        openclaw message send --channel discord --account robert --target ops-alerts \
        -m "Cron FAILED: ${JOB_NAME} (exit ${EXIT_CODE}) at ${TS}" 2>/dev/null | grep -v "level=warning" >/dev/null || true
    DISCORD_STATUS="attempted"

    mkdir -p /root/.openclaw/logs
    echo "[${TS}] job=${JOB_NAME} exit=${EXIT_CODE} telegram=${TELEGRAM_STATUS} discord=${DISCORD_STATUS}" \
        >> /root/.openclaw/logs/cron-alert.log
}

if [ "${1:-}" = "--notify-only" ]; then
    shift
    if [ "$#" -lt 2 ]; then
        usage
        exit 1
    fi
    JOB_NAME="$1"
    EXIT_CODE="$2"
    shift 2
    notify_failure "$JOB_NAME" "$EXIT_CODE" "$*"
    exit 0
fi

JOB_NAME="${1:?Usage: cron-alert.sh <job-name> <command> [args...]}"
shift
COMMAND="$@"

if [ -z "$COMMAND" ]; then
    usage
    exit 1
fi

# Run the command, capture output and exit code.
# CRON_ALERT_PARENT prevents nested cron-wrapper.sh calls from double-alerting.
export CRON_ALERT_PARENT=1
OUTPUT=$(eval "$COMMAND" 2>&1)
EXIT_CODE=$?
unset CRON_ALERT_PARENT

if [ $EXIT_CODE -ne 0 ]; then
    notify_failure "$JOB_NAME" "$EXIT_CODE" "$OUTPUT"
fi

exit $EXIT_CODE
