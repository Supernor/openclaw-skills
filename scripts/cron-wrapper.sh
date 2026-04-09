#!/usr/bin/env bash
# Alignment: cron wrapper that records command outcomes into ops.db for Bridge visibility.
# Role: run any cron target, capture exit code/output tail/duration, and persist a cron_outcomes row.
# Dependencies: reads the invoked command and shell output stream; writes /root/.openclaw/ops.db cron_outcomes entries;
# calls `date`, `mktemp`, `tail`, `sqlite3`, and the wrapped command itself.
# Key patterns: generic wrapper contract is `JOB_NAME command [args...]`; always preserves wrapped command exit status;
# stores only the last 5 output lines plus elapsed milliseconds so Bridge can show compact outcome history.
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

# Write to ops.db
sqlite3 "$OPS_DB" "
INSERT INTO cron_outcomes (job_name, exit_code, output_tail, duration_ms)
VALUES ('$(echo "$JOB_NAME" | tr "'" "_")', $EXIT_CODE, '$(echo "$TAIL" | tr "'" "_" | head -c 500)', $DURATION)
" 2>/dev/null

# Also echo the output so existing log redirects still work
echo "$OUTPUT"

exit $EXIT_CODE
