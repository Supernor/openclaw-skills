---
name: log-audit
description: Audit all OpenClaw log sources — persistence, retention, size, health. Runs log-audit.sh script.
version: 1.0.0
author: repo-man
tags: [logs, audit, monitoring, governance]
---

# log-audit

## Invoke
```
/log-audit
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/log-audit.sh
```

### 2. Format dashboard

Script outputs JSON covering all log sources. Format as:

```
📋 Log Audit — <date>

Gateway Log:
  Today: <size> | Persisted: <count> files (<size>) | Retention: 7 days
  Pruned: <N> old files this run

Sessions:
  <agent>: <files> files, <size>
  ...
  Total: <files> files, <size> | Pruned: <N> old sessions

Config Audit: <lines> entries | Last change: <date>
Cron Health: <total> recent runs, <failures> failures
Delivery Queue: <pending> pending, <failed> failed
Model Notifications: <lines> entries
Repo-Man Log: <lines> lines

Disk: <total>MB total log footprint

⚠️ Warnings:
  - <warning text>

🔧 Actions taken:
  - <action text>
```

If status is "ok" and no warnings, use a single line:
```
✅ Log Audit — All clear. <total>MB total. <N> files pruned.
```

### 3. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO log-audit "status: <ok|warning> warnings: <N>"
```

## What this script does automatically:
- **Persists** gateway logs from volatile `/tmp/` to `~/.openclaw/logs/gateway/`
- **Prunes** gateway logs older than 7 days
- **Prunes** session files older than 7 days (keeps min 3 per agent)
- **Rotates** config-audit.jsonl at 1000 lines (keeps last 500)
- **Rotates** repo-man.log at 500 lines (keeps last 200)
- **Checks** cron run history for failures
- **Checks** delivery queue for stuck/failed messages

## Notes
- Do NOT re-implement — always use the script
- Run nightly via cron, not on heartbeat
- If delivery queue has failures, investigate with: `cat ~/.openclaw/delivery-queue/failed/*.json | jq .`
- If cron failures detected, check: `cat ~/.openclaw/cron/runs/*.jsonl | jq -r 'select(.status=="error")'`
