---
name: model-failover-notify
description: Send model health notifications with color-coded containers and interactive buttons to #ops-alerts. Internal skill for heartbeat.
version: 4.0.0
author: repo-man
tags: [model-health, notifications, internal, components]
---

# model-failover-notify

## Purpose
Read `model-health-notifications.jsonl` for unread entries and send color-coded alerts with action buttons to **#ops-alerts**.

## Target
- **Channel:** `1477754571697688627` (#ops-alerts)

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

Send a **red container** with action buttons:

```json
{
  "action": "send",
  "channel": "discord",
  "channelId": "1477754571697688627",
  "components": {
    "container": {
      "accentColor": 15548997
    },
    "text": "🚨 **<provider>** — DOWN\n<reason> · since <relative_time>\nAffected profiles: <count>",
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

**Format notes:**
- Provider name bold and prominent — it's the first thing Robert reads
- Reason + time on one line, separated by `·`
- Use relative time ("5m ago", "2h ago") not ISO timestamps

Also run:
```bash
/home/node/.openclaw/scripts/incident-manager.sh open "<provider>" "<reason>"
```

### 4. For each RECOVERY notification

Send a **green container**, no buttons needed:

```json
{
  "action": "send",
  "channel": "discord",
  "channelId": "1477754571697688627",
  "components": {
    "container": {
      "accentColor": 5763719
    },
    "text": "✅ **<provider>** — RECOVERED\nWas down <duration> · reason: <reason>"
  }
}
```

Also run:
```bash
/home/node/.openclaw/scripts/incident-manager.sh close "<provider>"
```

### 5. Check fallback chain degradation

Read `model-health.json`. If 2+ providers are quarantined, send a **yellow container** with buttons:

```json
{
  "action": "send",
  "channel": "discord",
  "channelId": "1477754571697688627",
  "components": {
    "container": {
      "accentColor": 16776960
    },
    "text": "⚠️ **Fallback Chain Degraded** — <N>/4 providers down\nQuarantined: <list>\nActive: <list>",
    "reusable": true,
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

### 6. Button responses

When you receive a button click (message like `Clicked "Clear Quarantine".`):

- **"Clear Quarantine"** → Run `/model-clear <provider>`, confirm in thread
- **"View Logs"** → Run `gateway-log-query.sh --errors --limit 10`, post in thread
- **"Silence 1h"** → Update cursor to skip this provider for 1 hour, confirm in thread
- **"Clear All"** → Run `/model-clear all`, confirm in thread
- **"View Status"** → Run `/model-status`, post full dashboard in thread

Parse the original alert context from the conversation to determine which provider.

### 7. Update cursor
Write the current line count to the cursor file.

## Rules

- **Red = down, green = recovered, yellow = degraded** — never mix colors
- **Provider name first and bold** — it's the identifier Robert scans for
- **Relative times** — "5m ago" not "2026-03-01T20:15:00Z"
- **One card per event** — don't batch multiple failures into one message
- **`reusable: true`** on failure/degradation cards so buttons stay active
- Create threads on critical alerts for investigation context
