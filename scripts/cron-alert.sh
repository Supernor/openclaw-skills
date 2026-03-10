#!/usr/bin/env bash
# cron-alert.sh — Wrapper that runs a cron job and alerts on failure
# Usage: cron-alert.sh <job-name> <command> [args...]
# On failure: logs to ops.db incidents + sends Discord notification
# Intent: Observable [I13]. Created: 2026-03-09.
set -o pipefail

JOB_NAME="${1:?Usage: cron-alert.sh <job-name> <command> [args...]}"
shift
COMMAND="$@"

if [ -z "$COMMAND" ]; then
    echo "Usage: cron-alert.sh <job-name> <command> [args...]" >&2
    exit 1
fi

# Run the command, capture output and exit code
OUTPUT=$(eval "$COMMAND" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # Truncate output for incident description
    SHORT_OUTPUT=$(echo "$OUTPUT" | tail -5 | head -c 500)

    # Log to ops.db incidents (fallback to local file on failure)
    if ! /root/.openclaw/scripts/ops-db.py incident open "Cron failure: ${JOB_NAME}" \
        --severity medium \
        --desc "Exit code ${EXIT_CODE} at ${TS}. Output: ${SHORT_OUTPUT}" 2>/dev/null; then
        mkdir -p /root/.openclaw/logs
        echo "{\"ts\":\"${TS}\",\"source\":\"cron-alert\",\"job\":\"${JOB_NAME}\",\"exit_code\":${EXIT_CODE},\"output\":\"$(echo "$SHORT_OUTPUT" | tr '"' "'" | tr '\n' ' ')\"}" \
            >> /root/.openclaw/logs/cron-failures.jsonl
    fi

    # Write to health buffer
    echo "{\"ts\":\"${TS}\",\"source\":\"cron-alert\",\"job\":\"${JOB_NAME}\",\"exit_code\":${EXIT_CODE}}" \
        >> /root/.openclaw/health/buffer.jsonl 2>/dev/null || true

    # Send Discord notification via gateway
    docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway \
        openclaw message send --channel discord --account robert --target ops-alerts \
        -m "Cron FAILED: ${JOB_NAME} (exit ${EXIT_CODE}) at ${TS}" 2>/dev/null | grep -v "level=warning" || true
fi

exit $EXIT_CODE
