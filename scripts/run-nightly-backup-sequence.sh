#!/bin/bash

# Nightly backup sequence runner
# Runs scripts in order and collects JSON results

OUTPUT_FILE="/home/node/.openclaw/cron/runs/backup-results.json"
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
SCRIPTS_DIR="/home/node/.openclaw/scripts"

# Initialize results array
RESULTS=()

# Run key-drift-check.sh
OUTPUT_FILE="/tmp/key-drift-check.json"
chmod +x "$SCRIPTS_DIR/key-drift-check.sh"
if "$SCRIPTS_DIR/key-drift-check.sh" > "$OUTPUT_FILE" 2>&1; then
    RESULT=$(cat "$OUTPUT_FILE")
    RESULTS+=("$RESULT")
else
    ERROR_MSG="key-drift-check.sh failed with exit code $?"
    /home/node/.openclaw/scripts/log-event.sh ERROR repo-man-backups "$ERROR_MSG"
    RESULTS+=('{"error":"key-drift-check.sh failed","exit_code":$?,"timestamp":"$TIMESTAMP"}')
fi

# Run ws-backup.sh
OUTPUT_FILE="/tmp/ws-backup.json"
chmod +x "$SCRIPTS_DIR/ws-backup.sh"
if "$SCRIPTS_DIR/ws-backup.sh" > "$OUTPUT_FILE" 2>&1; then
    RESULT=$(cat "$OUTPUT_FILE")
    RESULTS+=("$RESULT")
else
    ERROR_MSG="ws-backup.sh failed with exit code $?"
    /home/node/.openclaw/scripts/log-event.sh ERROR repo-man-backups "$ERROR_MSG"
    RESULTS+=('{"error":"ws-backup.sh failed","exit_code":$?,"timestamp":"$TIMESTAMP"}')
fi

# Run env-backup.sh
OUTPUT_FILE="/tmp/env-backup.json"
chmod +x "$SCRIPTS_DIR/env-backup.sh"
if "$SCRIPTS_DIR/env-backup.sh" > "$OUTPUT_FILE" 2>&1; then
    RESULT=$(cat "$OUTPUT_FILE")
    RESULTS+=("$RESULT")
else
    ERROR_MSG="env-backup.sh failed with exit code $?"
    /home/node/.openclaw/scripts/log-event.sh ERROR repo-man-backups "$ERROR_MSG"
    RESULTS+=('{"error":"env-backup.sh failed","exit_code":$?,"timestamp":"$TIMESTAMP"}')
fi

# Run skills-backup.sh
OUTPUT_FILE="/tmp/skills-backup.json"
chmod +x "$SCRIPTS_DIR/skills-backup.sh"
if "$SCRIPTS_DIR/skills-backup.sh" > "$OUTPUT_FILE" 2>&1; then
    RESULT=$(cat "$OUTPUT_FILE")
    RESULTS+=("$RESULT")
else
    ERROR_MSG="skills-backup.sh failed with exit code $?"
    /home/node/.openclaw/scripts/log-event.sh ERROR repo-man-backups "$ERROR_MSG"
    RESULTS+=('{"error":"skills-backup.sh failed","exit_code":$?,"timestamp":"$TIMESTAMP"}')
fi

# Run repo-health.sh
OUTPUT_FILE="/tmp/repo-health.json"
chmod +x "$SCRIPTS_DIR/repo-health.sh"
if "$SCRIPTS_DIR/repo-health.sh" > "$OUTPUT_FILE" 2>&1; then
    RESULT=$(cat "$OUTPUT_FILE")
    RESULTS+=("$RESULT")
else
    ERROR_MSG="repo-health.sh failed with exit code $?"
    /home/node/.openclaw/scripts/log-event.sh ERROR repo-man-backups "$ERROR_MSG"
    RESULTS+=('{"error":"repo-health.sh failed","exit_code":$?,"timestamp":"$TIMESTAMP"}')
fi

# Combine all results into final JSON array
FINAL_JSON=$(jq -s '.' <<< "\$(printf '%s\n' "${RESULTS[@]}")")

# Write to output file
mkdir -p /home/node/.openclaw/cron/runs
printf '%s\n' "$FINAL_JSON" > /home/node/.openclaw/cron/runs/backup-results.json

echo "Nightly backup sequence completed. Results written to /home/node/.openclaw/cron/runs/backup-results.json"
