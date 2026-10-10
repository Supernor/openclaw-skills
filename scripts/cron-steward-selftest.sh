#!/usr/bin/env bash
# === INTENT ===
# Deliberately-failing test cron for cron-incident-steward: fails (stderr + exit 1) while its work directory is missing, succeeds once it exists.
# The steward's missing-directory fixer should create the directory, re-run this, and close the incident as recovered. Never scheduled to fire (Feb 31).
# === END ===
D=/root/.openclaw/tmp/cron-steward-selftest
if ! echo "selftest ok $(date -u +%FT%TZ)" > "$D/out.txt"; then
  echo "cron-steward-selftest: cannot write $D/out.txt: No such file or directory" >&2
  exit 1
fi
echo "selftest wrote $D/out.txt"
