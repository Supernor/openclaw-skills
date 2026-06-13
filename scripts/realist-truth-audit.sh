#!/bin/bash
# Realist Truth Audit — weekly Tuesday 6:30am UTC
# Runs truth-audit across all categories via spec-realist agent
#
# === INTENT: dead-class regression guard (added 2026-06-12) ===
# 8 issue-register rows were marked 'invalid' because their CLASS of
# false-positive was fixed at the generator (executor verifier keywords,
# NOOP sentinel handling). Path-to-valid-truth: if NEW rows matching those
# dead signatures appear, the fix regressed — surface it to the Realist.
# ==============================================================
RESURRECTED=$(sqlite3 /root/.openclaw/ops.db "
  SELECT COUNT(*) FROM issues
  WHERE logged_at >= datetime('now','-7 day')
    AND logged_at > '2026-06-12T16:00:00'  -- only rows born AFTER the class fixes shipped
    AND status != 'invalid'                -- already-triaged rows are not resurrections
    AND (description LIKE '%failure signal ''read-only''%'
      OR description LIKE '%failure signal ''readonly''%'
      OR description LIKE '%failure signal ''blocked''%'
      OR description LIKE '%Registered plugin command%'
      OR (description LIKE '%NOOP%' AND description LIKE '%Empty or trivial%'));" 2>/dev/null || echo 0)

GUARD_NOTE=""
if [ "${RESURRECTED:-0}" -gt 0 ]; then
  GUARD_NOTE=" PRIORITY: ${RESURRECTED} new issue rows this week match verifier false-positive signatures that were FIXED 2026-06-12 (chart issue-executor-verifier-false-positive-20260612) — the fix has regressed. Investigate host-ops-executor.py verify logic first and report."
  echo "[$(date -u +%FT%TZ)] DEAD-CLASS REGRESSION: ${RESURRECTED} resurrected false-positive rows" >> /root/.openclaw/logs/realist-truth-audit.log
fi

oc agent --agent spec-realist -m "Run /truth-audit all categories, verbose.${GUARD_NOTE}"
