---
name: dashboard-update
description: Update the pinned dashboard message in #ops-dashboard with current system status. Internal skill for nightly cron.
version: 1.0.0
author: repo-man
tags: [dashboard, monitoring, internal]
---

# dashboard-update

## Purpose
Refresh the pinned status summary in **#ops-dashboard** with current system health.

## Target Channel
**#ops-dashboard** — Channel ID: `1477754431780028598`
**Pinned Message ID:** `1477754773951352903`

## Steps

### 1. Gather data
Run these scripts and read these files:

```bash
# Model health
cat /home/node/.openclaw/model-health.json | jq .

# Log audit (run fresh or read last result)
/home/node/.openclaw/scripts/log-audit.sh

# Key drift
/home/node/.openclaw/scripts/key-drift-check.sh

# Repo health
/home/node/.openclaw/scripts/repo-health.sh
```

### 2. Format dashboard message

```
📊 **OpenClaw Operations Dashboard**
_Updated: <timestamp>_

**Providers**
<emoji> <provider>: <status> (<reason if not healthy>)
...

**Key Drift:** <status> — <missing>/<total> keys present
**Disk:** <total>MB — Gateway: <N>MB, Sessions: <N>MB
**Backups:** ws: <age>, env: <age>, skills: <age>
**Repos:** config: <status>, workspace: <status>, skills: <status>
**Logs:** <warnings count> warnings — <details if any>
**Cron:** Last run: <status> at <time>

_Next nightly: 03:00 UTC_
```

Use these status emojis:
- ✅ Healthy/OK
- ⚠️ Warning/Degraded
- 🚨 Error/Down
- ⏳ Pending/Unknown

### 3. Edit the pinned message
Edit message `1477754773951352903` in channel `1477754431780028598` with the new content.

Do NOT delete and re-create — edit in place to preserve the pin.

### 4. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO dashboard-update "Updated ops-dashboard"
```

## When to run
- After nightly cron completes (step 7 of nightly run)
- On demand via `/dashboard-update` if needed

## Notes
- Keep the message under Discord's 2000 character limit
- If data is stale (scripts fail), show last known good + warning
- This is the "glance" view — link to #ops-nightly for details
