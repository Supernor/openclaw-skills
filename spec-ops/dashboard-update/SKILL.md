---
name: dashboard-update
description: Update the pinned dashboard message in #ops-dashboard with current system status using color-coded containers. Internal skill for nightly cron.
version: 3.0.0
author: repo-man
tags: [dashboard, monitoring, internal, components]
---

# dashboard-update

## Purpose
Refresh the pinned status summary in **#ops-dashboard** with current system health.

## Template
Read `~/.openclaw/templates/dashboard-update.txt` for Discord formatting templates and color rules.

## Registry
```bash
CHANNEL=$(jq -r '.discord.channels."ops-dashboard"' ~/.openclaw/registry.json)
PIN_MSG=$(jq -r '.discord.pins.dashboard' ~/.openclaw/registry.json)
```

## Steps

### 1. Gather data
```bash
cat /home/node/.openclaw/model-health.json | jq .
/home/node/.openclaw/scripts/key-drift-check.sh
/home/node/.openclaw/scripts/repo-health.sh
/home/node/.openclaw/scripts/log-audit.sh
```

### 2. Determine overall status
- **Green:** All providers healthy, no key drift, all repos reachable, no log warnings
- **Yellow:** 1 provider quarantined OR log warnings OR stale backups (>48h)
- **Red:** 2+ providers quarantined OR key drift OR repo unreachable OR backup failure

### 3. Edit pinned message
Use the template from `templates/dashboard-update.txt`. Fill placeholders with gathered data. Send as container edit to the pinned message ID from registry.

Traffic light colors: Green `5763719` / Yellow `16776960` / Red `15548997`

### 4. Rules
- Always edit message — never delete/recreate
- Under 1500 chars
- Providers on one line with `·` separator, drop provider prefixes
- Only expand detail on problem sections

### 5. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO dashboard-update "Updated: <green|yellow|red>"
```

Intent: Observable [I13]. Purpose: [P-TBD].
