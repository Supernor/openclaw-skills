---
name: log-event
description: Internal structured logging utility. Runs log-event.sh to write timestamped entries to local log and push WARN+ to ERRORS.md on GitHub. Called by other skills, not directly.
version: 3.0.0
author: repo-man
tags: [internal, logging, audit, errors]
---

# log-event

## Purpose
Write a structured log entry for any skill execution. This is the system's
logging backbone — every other skill calls this to record what happened.
INFO stays local. WARN and above get pushed to ERRORS.md on GitHub so
failures are visible even if the container is rebuilt.

## When to use
- Called by OTHER skills after execution — not invoked directly by users
- Every skill should call this as its final step (see `/last-run-update`)
- When you need to record an error with full context (exit code, stderr)

## Usage

```bash
/home/node/.openclaw/scripts/log-event.sh <LEVEL> <SKILL> <MESSAGE> [EXIT_CODE] [STDERR]
```

### Parameters

| Param | Required | Values | Example |
|-------|----------|--------|---------|
| LEVEL | Yes | INFO, WARN, ERROR, FATAL | `ERROR` |
| SKILL | Yes | Skill name that triggered the log | `backup-suite` |
| MESSAGE | Yes | What happened (keep under 200 chars) | `push failed: auth expired` |
| EXIT_CODE | No | Numeric exit code from failed command | `128` |
| STDERR | No | Captured stderr output from the failure | `fatal: Authentication failed` |

### Routing behavior

| Level | Local log | ERRORS.md on GitHub | When to use |
|-------|-----------|-------------------|-------------|
| INFO | Yes | No | Normal operation, success confirmations |
| WARN | Yes | Yes (pushed) | Degraded but functional — needs attention |
| ERROR | Yes | Yes (pushed) | Something failed, skill could not complete |
| FATAL | Yes | Yes (pushed) | Critical failure, immediate human attention |

### Output

Expected: `{"logged":true,"level":"<LEVEL>","skill":"<SKILL>","timestamp":"<ISO8601>"}`

### Files written

- **Local log**: `/home/node/.openclaw/workspace-spec-github/logs/repo-man.log` (always)
- **ERRORS.md**: `/home/node/.openclaw/repos/openclaw-config/logs/ERRORS.md` (WARN+ only, pushed to GitHub)

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Script exits with "Usage:" error | Missing required parameters (LEVEL, SKILL, or MESSAGE) | All three are required. Check calling skill passes all three. |
| "No such file or directory" for local log | logs/ directory missing | Script creates it automatically via `mkdir -p`. If still failing, check permissions on workspace-spec-github dir. |
| ERRORS.md push fails silently | Git auth broken or ERRORS.md file doesn't exist | The `|| true` in the script prevents hard failures. Run `/github-guardian` to fix auth. Push will succeed next time. |
| Duplicate entries in ERRORS.md | Multiple skills logging the same error | Not harmful — better to over-log than under-log. |

**ERRORS.md push failure deep dive**
- ERROR MEANING: The script commits to ERRORS.md locally but the git push to GitHub fails. The entry is NOT lost — it's committed locally and will be pushed with the next successful push.
- HISTORY: Push failures correlate with GH_TOKEN issues. Same root cause as other backup push failures.
- FIX: Run `/github-guardian`. No data loss — local commits accumulate and push together.

## Rules
- NEVER write to log files manually — always use this script
- NEVER truncate or rotate logs manually — ERRORS.md is an append-only audit trail
- WARN+ entries prepend (latest first) in ERRORS.md for easy scanning
- The script removes the "No errors logged yet" placeholder automatically on first real entry

## Related
- `/last-run-update` — complementary logging (LAST_RUN.md audit trail)
- `/backup-suite` — calls this to log each backup phase result
- `/github-guardian` — fixes push failures when WARN+ entries can't reach GitHub
- `chart search "logging"` — operational knowledge about the logging system

## Notes
- This script is designed to NEVER cause a calling skill to fail. Push failures are caught with `|| true`. The worst case is that WARN+ entries stay local until the next successful push.
- The local log at `repo-man.log` is the authoritative record. ERRORS.md on GitHub is a remote mirror of the important entries.

Intent: Observable [I13].
