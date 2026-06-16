#!/usr/bin/env bash
# bootstrap-size-guard-cron.sh — daily: lossless-trim the workspace bootstrap MD
# files and ALERT (Bridge-visible issue) on any that still exceed the 11,500 cap and
# therefore need a human/agent content cut or wiki-offload. Owner: Quartermaster.
#
# WHY a cron: bootstrap files regrow silently between sessions (Relay went 11,493 ->
# 12,239 = actively truncating in 3 days). Lossless --fix auto-handles blank-line/dup
# bloat; anything still over is a real content decision, surfaced not auto-cut.
# Exit 0 always (the issue is the signal); uses RESULT_LABEL so cron_outcomes isn't
# misread as broken (see cron-wrapper.sh convention).
set -uo pipefail

OUT=$(python3 /root/.openclaw/scripts/bootstrap-size-guard.py --fix 2>&1)
RC=$?
echo "$OUT"

if [ "$RC" = "2" ]; then
    REMAIN=$(echo "$OUT" | sed -n '/NEEDS CONTENT CUT/,$p' | tr '\n' ' ' | cut -c1-400)
    issue-log log "Bootstrap MD over the 11,500 cap after lossless trim — needs content cut or wiki-offload: ${REMAIN}" --severity medium 2>/dev/null || true
    echo "RESULT_LABEL: alerted"
fi
exit 0
