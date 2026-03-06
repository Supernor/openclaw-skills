---
name: log-event
description: "Internal logging utility. Runs log-event.sh script. Called by other skills, not directly."
version: 2.0.0
author: repo-man
tags: [internal, logging]
---

# log-event

## Usage (called by other skills)

```bash
/home/node/.openclaw/scripts/log-event.sh <LEVEL> <SKILL> <MESSAGE> [EXIT_CODE] [STDERR]
```

Levels: INFO, WARN, ERROR, FATAL

- INFO → local log only
- WARN+ → local log + ERRORS.md on GitHub (auto-pushed)

## Notes
- Script handles all log formatting, file I/O, and GitHub push
- Do NOT write to logs manually — always use this script
- Never truncate logs
