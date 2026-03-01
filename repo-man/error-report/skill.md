---
name: error-report
description: Pull recent errors from the local log and ERRORS.md, format them, and send to Discord. Invoke with /error-report or /error-report <N> for last N entries.
version: 1.0.0
author: repo-man
tags: [logging, errors, reporting]
---

# error-report

## Invoke

```
/error-report          # Last 10 WARN+ entries
/error-report 25       # Last 25 entries
/error-report today    # All entries from today (UTC)
```

## Steps

### 1. Read from local log
```bash
LOG="/home/node/.openclaw/workspace-spec-github/logs/repo-man.log"
grep -E '^\[.+\] (WARN|ERROR|FATAL)' "$LOG" | tail -N
```

### 2. Also read from GitHub ERRORS.md
```bash
cat /home/node/.openclaw/workspace-spec-github/openclaw-config/logs/ERRORS.md | head -100
```

### 3. Format and send to Discord

If no errors found: `[Repo-Man] error-report: No WARN/ERROR/FATAL entries found in requested range. All clear.`

## Notes
- This skill does not modify any logs. Read-only.
- If local log is missing: report that fact as part of the output.
