---
name: last-run-update
description: Update LAST_RUN.md with timestamp and outcome after every skill execution. Creates an audit trail of Repo-Man's activity.
version: 1.0.0
author: repo-man
tags: [audit, logging, session]
---

# last-run-update

## Purpose
Maintain LAST_RUN.md as a running log of what Repo-Man did and when.
This is the audit trail — if Robert asks "when did backups last run?"
or "what has Repo-Man been doing?", this file answers immediately.

## When to use
- After EVERY skill execution (SOUL.md mandates this)
- This is the last step of every task, not a standalone skill

## How to update

Append a line to LAST_RUN.md in your workspace:

```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | <skill-name> | <PASS/FAIL/ERROR> | <brief summary>" >> /home/node/.openclaw/workspace-spec-github/LAST_RUN.md
```

### Format
```
TIMESTAMP | SKILL | STATUS | SUMMARY
2026-05-18T03:00:15Z | backup-suite | PASS | env=PASS skills=PASS ws=PASS, all repos fresh
2026-05-18T03:01:00Z | key-drift-check | PASS | 12/12 keys present
2026-05-18T06:00:30Z | upstream-check | PASS | no new activity
2026-05-18T15:00:00Z | backup-suite | FAIL | skills-backup push failed (auth), escalated
```

### Rules
- One line per skill execution
- Always include the status (PASS/FAIL/ERROR)
- Keep summaries under 80 characters
- Never delete old entries — this is an append-only audit log
- If the file doesn't exist, create it with a header:
  ```
  # LAST_RUN.md — Repo-Man Activity Log
  # Format: TIMESTAMP | SKILL | STATUS | SUMMARY
  ```

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| "Permission denied" on append | File owned by root after host edit | `chown 1000:1000 /home/node/.openclaw/workspace-spec-github/LAST_RUN.md` |
| File doesn't exist | First run or workspace was rebuilt | Create it with the header (see Rules above) |
| File is huge (>1000 lines) | Many months of entries | Archive old entries, keep last 200 lines |

## Related
- `/session-wrap` — calls this as part of session cleanup
- SOUL.md Operating Procedure step 5: "Update LAST_RUN.md after every skill run"
- `chart read reading-repoman-skills-audit-20260518` — audit that created this skill

Intent: Observable [I13].
