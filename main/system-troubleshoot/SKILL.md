---
name: system-troubleshoot
description: Zero-token diagnosis of common system issues. Run when things look stuck.
tags: [ops, troubleshoot, health, diagnosis, zero-cost]
version: 1.0.0
---

# system-troubleshoot

Diagnose why the system isn't working. Zero token cost — pure bash + SQLite.

## When to use
- Tasks stuck in pending (not promoting to in_progress)
- Executor seems dead or duplicated
- Robert says "workers aren't doing anything"
- Stability monitor detects tasks stuck >30 min
- Any time you're unsure about system health

## How to run
```bash
bash /root/.openclaw/scripts/system-troubleshoot.sh
```

## What it checks (9 checks)
1. Executor running? (0 = dead, >1 = orphans)
2. Pending tasks stuck? (quarantined agents, dead blocked_by)
3. In-progress stuck >15 min? (killed executor left zombies)
4. Concurrency full? (MAX_CONCURRENT=2 met, shows oldest)
5. Gateway down? (OOM, config error)
6. Bridge responding? (port conflict, crash)
7. Codex health? (OAuth expired, rate limited)
8. Orphan processes? (duplicates of any monitored process)
9. Log spam? (executor log >10MB)

## Output format
For each issue: PROBLEM → CAUSE → FIX (actionable command)
Summary: N issue(s) found

## Self-improvement
This skill gets better each time someone discovers a new failure mode:
1. Diagnose the issue manually
2. Add a check to system-troubleshoot.sh
3. Chart the failure pattern for future reference
