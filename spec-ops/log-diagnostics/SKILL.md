---
name: log-diagnostics
description: Scan gateway logs for recurring error patterns, group and classify findings, escalate critical issues to Reactor.
version: 1.0.0
author: reactor
tags: [logs, errors, monitoring, diagnostics, escalation]
---

# log-diagnostics

## Invoke
```
/log-diagnostics
```

## What it does

Host-side Python script scans the last 30 minutes of gateway logs for known error patterns. Groups identical errors, classifies severity (critical/warning/info), and writes findings to ops.db.

- **Critical** findings route to Reactor for auto-fix (e.g. codex-reauth)
- **Warning** findings route to Ops Officer for triage via MCP/lanes
- **Info** findings are logged only
- Deduplicates: same pattern won't re-alert within 6 hours

## Runs automatically

Cron: every 30 minutes on host.

## On-demand use

When you spot something suspicious through other channels and want a fresh log scan:

1. Note what you're investigating
2. The host cron handles execution -- check results in ops.db:
   ```
   ops-db.py query "SELECT payload FROM agent_results WHERE type='log-diagnostics' ORDER BY id DESC LIMIT 1"
   ```
3. If critical findings exist, check if Reactor has picked them up
4. If warning findings are yours, investigate via chart search and issue-log

## Pattern config

Error patterns are configurable at `/root/.openclaw/config/error-patterns.json` on host.
Add new patterns there -- no code changes needed.

## Log

`/root/.openclaw/logs/log-diagnostics.log` on host.

Intent: Observable [I13]. Purpose: P04 (System Visibility).
