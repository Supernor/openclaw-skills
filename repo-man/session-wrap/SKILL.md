---
name: session-wrap
description: End-of-session cleanup — update LAST_RUN.md, commit workspace changes, verify no loose ends. Mandatory final step of every Repo-Man session.
version: 2.0.0
author: repo-man
tags: [session, cleanup, audit, mandatory]
---

# session-wrap

## Purpose
Clean up after a Repo-Man session. Ensures all work is logged, workspace
changes are committed, and nothing is left in a half-done state. This is
the LAST thing you do before returning to Captain — SOUL.md step 9.

## When to use
- At the end of EVERY Repo-Man session (mandatory per SOUL.md)
- When your task is complete and you're ready to hand off
- Even if the task failed — log the failure, then wrap

## Steps

### 1. Update LAST_RUN.md
Log everything you did this session using the `/last-run-update` format:
```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | <skill> | <status> | <summary>" >> /home/node/.openclaw/workspace-spec-github/LAST_RUN.md
```
One line per skill you executed. Include failures — they're part of the audit trail.

### 2. Check for uncommitted workspace changes
```bash
cd /home/node/.openclaw/workspace-spec-github
git status -s
```
If there are changes (LAST_RUN.md updates, skill edits, etc.):
```bash
git add -A
git commit -m "[repo-man] session wrap $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

### 3. Verify no stuck state
Check that you didn't leave anything half-done:
- No open git merges or rebases in backup repos
- No lock files you created that weren't cleaned up
- Any ERROR-level issues should be logged to ops.db or charted

### 4. Summary to Captain
Return a brief summary of what you accomplished:
```
[Repo-Man] Session complete.
  Skills run: <list>
  Errors: <count> (<brief description if any>)
  LAST_RUN.md: updated
```

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| "Permission denied" on LAST_RUN.md | File owned by root after host edit | `chown 1000:1000 /home/node/.openclaw/workspace-spec-github/LAST_RUN.md` |
| LAST_RUN.md doesn't exist | First run or workspace rebuilt | Create with header: `echo "# LAST_RUN.md" > LAST_RUN.md` |
| git commit fails | No git user configured in container | `git config user.email "repo-man@openclaw.local" && git config user.name "Repo-Man"` |
| Workspace not a git repo | workspace-spec-github was never initialized | `cd workspace-spec-github && git init && git add -A && git commit -m "init"` |

## Related
- `/last-run-update` — the logging format this skill uses
- SOUL.md Operating Procedure step 9: "End session: run /session-wrap"
- `chart read reading-repoman-autonomy-20260518` — full autonomy setup context

Intent: Observable [I13].
