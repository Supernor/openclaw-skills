#!/usr/bin/env bash
# cron-wrapper.sh — Wraps cron commands to capture and log outcomes.
# Usage: cron-wrapper.sh "job-name" command [args...]
#
# Captures: exit code, last 5 lines of output, duration.
# Writes to ops.db cron_outcomes table.
# Use this for all crons that need outcome visibility on Bridge.
#
# Example crontab entry:
#   */10 * * * * /root/.openclaw/scripts/cron-wrapper.sh "issue-pipeline" /root/.openclaw/scripts/issue-pipeline-tick.sh

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
