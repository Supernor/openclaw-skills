#!/usr/bin/env bash
# bootstrap-size-guard-cron.sh — daily: lossless-trim the workspace bootstrap MD files and
# file a PER-FILE ops.db issue (with a structured re-check) for any that still exceed the
# 11,500 cap and therefore need a human/agent content cut or wiki-offload. Owner: Quartermaster.
#
# WHY ops.db (not bash `issue-log`): the self-heal loop consumes ops.db issues. Each filed
# issue carries recheck_kind=file_size_max so the loop can PROVE the fix and — while
# selfheal_mode=shadow — hold the proposed trim for Robert's approval before it sticks. The
# bash `issue-log` only appends JSONL, invisible to the ops.db pipeline (the old call did that).
# WHY a cron: bootstrap files regrow silently between sessions (Relay went 11,493 -> 12,239 in
# 3 days). Lossless --fix auto-handles blank-line/dup bloat; anything still over is a real
# content decision, surfaced not auto-cut. Exit 0 always (the issue is the signal); RESULT_LABEL
# so cron_outcomes isn't misread as broken (see cron-wrapper.sh convention).
set -uo pipefail

GUARD=/root/.openclaw/scripts/bootstrap-size-guard.py
ILOG=/root/.openclaw/scripts/issue-log.py

OUT=$(python3 "$GUARD" --fix 2>&1)
RC=$?
echo "$OUT"

# --fix writes files as root (cron runs as root) -> flip the workspace bootstrap files back to
# ubuntu:ubuntu (uid 1000 = container 'node'); root-owned files break the container's writes
# to the bind mount. Idempotent; harmless on unchanged files. (boy-scout: pre-existing gap.)
chown ubuntu:ubuntu \
  /root/.openclaw/workspace*/SOUL.md /root/.openclaw/workspace*/AGENTS.md \
  /root/.openclaw/workspace*/TOOLS.md /root/.openclaw/workspace*/MEMORY.md \
  /root/.openclaw/workspace*/IDENTITY.md /root/.openclaw/workspace*/USER.md \
  /root/.openclaw/workspace*/HEARTBEAT.md /root/.openclaw/workspace*/BOOTSTRAP.md 2>/dev/null || true

if [ "$RC" = "2" ]; then
    # Each file still over the cap after lossless trim becomes ONE ops.db issue carrying a
    # file_size_max re-check (the loop's proof + shadow-approval gate). Dedup is by fingerprint,
    # so re-running daily on the same over-cap file does not pile up duplicate issues.
    echo "$OUT" | sed -n '/NEEDS CONTENT CUT/,$p' | grep -E '^[[:space:]]+[0-9]+[[:space:]]+/' | \
    while read -r N P; do
        python3 "$ILOG" log \
          "Bootstrap file $P is $N chars, over the 11,500 cap after lossless trim — needs a content cut or wiki-offload." \
          --severity high --system bootstrap --found-by bootstrap-size-guard \
          --suggested-fix "Trim $P to 11,500 chars or fewer by offloading detail to the wiki or removing redundant/duplicate lines. Do NOT delete sections wholesale or remove operational rules/boundaries." \
          --recheck-kind file_size_max --recheck-params "{\"path\":\"$P\",\"max\":11500}" \
          >/dev/null 2>&1 || true
    done
    echo "RESULT_LABEL: alerted (filed ops.db issues with file_size_max re-checks)"
fi
exit 0
