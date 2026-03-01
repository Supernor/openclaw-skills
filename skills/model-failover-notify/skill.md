---
name: model-failover-notify
description: Send model health notifications with interactive buttons to #ops-alerts. Internal skill for heartbeat.
version: 3.0.0
author: repo-man
tags: [model-health, notifications, internal, components]
---

# model-failover-notify

## Purpose
Read `model-health-notifications.jsonl` for unread entries and send interactive alerts to **#ops-alerts**.

## Target Channel
**#ops-alerts** — Channel ID: `1477754571697688627`

## Steps

### 1. Read cursor
```bash
CURSOR_FILE="/home/node/.openclaw/model-health-notify-cursor.txt"
NOTIF_FILE="/home/node/.openclaw/model-health-notifications.jsonl"
```
If cursor file exists, read the line number. Otherwise start from 0.

### 2. Read new notifications
Read lines from `$NOTIF_FILE` starting after the cursor position.

### 3. For each FAILURE notification

Send to #ops-alerts using **Discord components** (buttons for quick actions):

```json
{
  "action": "send",
  "channel": "discord",
  "channelId": "1477754571697688627",
  "components": {
    "text": "🚨 **Provider Down: <provider>**\nReason: <reason>\nSince: <timestamp>\nAffected profiles: <count>",
    "reusable": true,
    "blocks": [
      {
        "type": "actions",
        "buttons": [
          { "label": "Clear Quarantine", "style": "success" },
          { "label": "View Logs", "style": "primary" },
          { "label": "Silence 1h", "style": "secondary" }
        ]
      }
    ]
  }
}
```

**When Robert clicks a button:**
- **"Clear Quarantine"** → Run `/model-clear <provider>` and confirm in thread
- **"View Logs"** → Run `gateway-log-query.sh --errors --limit 10` and post results in thread
- **"Silence 1h"** → Update cursor to skip this provider for 1 hour, confirm in thread

Also run:
```bash
/home/node/.openclaw/scripts/incident-manager.sh open "<provider>" "<reason>"
```

### 4. For each RECOVERY notification

Send plain message (no buttons needed):
```
✅ **Provider Recovered: <provider>**
Down since: <timestamp>
Duration: <calculated>
```

Also run:
```bash
/home/node/.openclaw/scripts/incident-manager.sh close "<provider>"
```

### 5. Check fallback chain degradation
Read `model-health.json`. If 2+ providers are quarantined, send:
```json
{
  "action": "send",
  "channel": "discord",
  "channelId": "1477754571697688627",
  "components": {
    "text": "⚠️ **Fallback Chain Degraded**\nQuarantined: <list>\nActive: <list>",
    "blocks": [
      {
        "type": "actions",
        "buttons": [
          { "label": "Clear All", "style": "danger" },
          { "label": "View Status", "style": "primary" }
        ]
      }
    ]
  }
}
```

**When clicked:**
- **"Clear All"** → Run `/model-clear all`
- **"View Status"** → Run `/model-status` and post full dashboard in thread

### 6. Update cursor
Write the current line count to the cursor file.

## Button Response Format

When you receive a button click (message like `Clicked "Clear Quarantine".`), parse the original alert context from the conversation to determine which provider. Then execute the action and reply in the same thread.

## Notes
- Always send to channel ID `1477754571697688627` (#ops-alerts)
- Use `reusable: true` on components so buttons stay active
- Create threads on critical alerts for investigation
- This runs on heartbeat — keep the polling fast, only format when there are new entries
