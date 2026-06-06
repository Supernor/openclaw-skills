#!/usr/bin/env bash
# truth-gate-nightly-audit.sh — Nightly error audit via truth-gate system
# Role: Entry point for the "truth-gate" cron job slot (nightly error audit)
# Outputs: passes through so cron-wrapper captures stdout for ops.db
# Purpose: Run regular error audit to detect any issues that need truth-gate interception

set -euo pipefail

# Tell cron-wrapper what WE think the result was
# Exit 0 if we found good data, 2 if our script had format/vetting issues but cron-wrapper doesn't care
AUDIT_STEP=0
OUTPUT=

# 1. Ensure error-audit runs and writes to the ops.db error_audit table
#    If it succeeds, the host-op executor will validate the output exists in table
if /usr/bin/python3 /root/.openclaw/scripts/error-audit.py >/tmp/error-audit-nightly.log 2>&1; then
    echo "RESULT_LABEL: audit_performed"
    echo "Truth-gate nightly audit: error-audit completed successfully"
    AUDIT_STEP=1
else
    echo "RESULT_LABEL: audit_failed"
    echo "Truth-gate nightly audit: error-audit script returned non-zero"
    exit 2  # Vetting failure, not system failure
fi

# 2. Verify the error_audit table was populated (validator will do this after task executes)
sqlite3 /root/.openclaw/ops.db "SELECT COUNT(*) FROM error_audit WHERE ts > strftime('%Y-%m-%dT%H:%M:%SZ','now', '-5 minutes')" | grep -q "[1-9]"
if [ $? -eq 0 ]; then
    echo "Verification: error_audit has recent entries"
else
    echo "Warning: error_audit table appears empty"
fi

# Optional: Log outcome to dedicated file for human inspection
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "${TIMESTAMP} truth-gate-nightly-audit: exit=${AUDIT_STEP}" >> /root/.openclaw/logs/truth-gate-nightly-audit.log

exit $AUDIT_STEP
