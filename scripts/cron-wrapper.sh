#!/usr/bin/env bash
# Alignment: cron wrapper that records command outcomes into ops.db for Bridge visibility.
# Role: run any cron target, capture exit code/output tail/duration, and persist a cron_outcomes row.
# Dependencies: reads the invoked command and shell output stream; writes /root/.openclaw/ops.db cron_outcomes entries;
# calls `date`, `mktemp`, `tail`, `sqlite3`, and the wrapped command itself.
# Key patterns: generic wrapper contract is `JOB_NAME command [args...]`; always preserves wrapped command exit status;
# stores only the last 5 output lines plus elapsed milliseconds so Bridge can show compact outcome history.
#
# EXIT CODE → RESULT LABEL:
#   Scripts can output a line starting with "RESULT_LABEL:" to set a human-readable label.
#   If not provided, cron-wrapper maps:
#     0 → "ok"
#     1 → "error" (override with RESULT_LABEL: in your script)
#     2 → "error"
#     124 → "timeout"
#     137 → "killed_oom"
#     143 → "killed_signal"
#
#   Example: stability-monitor.sh outputs "RESULT_LABEL: alerted" on exit 1
#   because exit 1 means "I detected a problem and sent an alert" — not a failure.
#
# WHY THIS MATTERS:
#   Without labels, agents analyzing cron_outcomes interpret exit_code=1 as "broken."
#   Labels let agents understand WHAT happened without reading the script source.
#   This was discovered during the Month of May Automation Audit when 3 AI engines
#   all misdiagnosed stability-monitor's exit 1 (alerts) as system failures.
#
# Reference: /root/.openclaw/docs/policy-context-injection.md

set -o pipefail

JOB_NAME="${1:?Usage: cron-wrapper.sh JOB_NAME command [args...]}"
shift

OPS_DB="/root/.openclaw/ops.db"
START_MS=$(date +%s%3N 2>/dev/null || echo 0)

# Run the actual command, capture output
OUTPUT=$("$@" 2>&1)
EXIT_CODE=$?

END_MS=$(date +%s%3N 2>/dev/null || echo 0)
DURATION=$((END_MS - START_MS))

# Get last 5 lines of output for the tail
TAIL=$(echo "$OUTPUT" | tail -5)

# Determine result_label
# 1. Check if script explicitly set one via RESULT_LABEL: line
RESULT_LABEL=$(echo "$OUTPUT" | grep -m1 "^RESULT_LABEL:" | sed 's/^RESULT_LABEL: *//' | head -c 30)

# 2. If not set, map from exit code
if [ -z "$RESULT_LABEL" ]; then
    case $EXIT_CODE in
        0)   RESULT_LABEL="ok" ;;
        124) RESULT_LABEL="timeout" ;;
        137) RESULT_LABEL="killed_oom" ;;
        143) RESULT_LABEL="killed_signal" ;;
        *)   RESULT_LABEL="error" ;;
    esac
fi

# Write to ops.db
sqlite3 "$OPS_DB" "
INSERT INTO cron_outcomes (job_name, exit_code, output_tail, duration_ms, result_label)
VALUES ('$(echo "$JOB_NAME" | tr "'" "_")', $EXIT_CODE, '$(echo "$TAIL" | tr "'" "_" | head -c 500)', $DURATION, '$(echo "$RESULT_LABEL" | tr "'" "_")')
" 2>/dev/null

# Also echo the output so existing log redirects still work
echo "$OUTPUT"

exit $EXIT_CODE
