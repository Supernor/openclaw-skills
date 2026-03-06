---
name: model-failover-notify
description: Send model health notifications with color-coded containers and interactive buttons to #ops-alerts. Internal skill for heartbeat.
version: 5.0.0
author: repo-man
tags: [model-health, notifications, internal, components]
---

# model-failover-notify

## Purpose
Read `model-health-notifications.jsonl` for unread entries and send color-coded alerts to **#ops-alerts**.

## Template
Read `~/.openclaw/templates/model-failover-notify.txt` for Discord card formats, button configs, colors, and handler instructions.

## Registry
```bash
CHANNEL=$(jq -r '.discord.channels."ops-alerts"' ~/.openclaw/registry.json)
```

## Steps

### 1. Read cursor and new notifications
```bash
CURSOR_FILE="/home/node/.openclaw/model-health-notify-cursor.txt"
NOTIF_FILE="/home/node/.openclaw/model-health-notifications.jsonl"
```
Read lines after cursor position.

### 2. For each FAILURE notification
Send **red** container (`15548997`) with action buttons per template. Run:
```bash
/home/node/.openclaw/scripts/incident-manager.sh open "<provider>" "<reason>"
```

### 3. For each RECOVERY notification
Send **green** container (`5763719`), no buttons. Run:
```bash
/home/node/.openclaw/scripts/incident-manager.sh close "<provider>"
```

### 4. Check fallback chain degradation
If 2+ providers quarantined in `model-health.json`, send **yellow** container (`16776960`) with buttons per template.

### 5. Handle button clicks
See template file for button→action mappings.

### 6. Update cursor
Write current line count to cursor file.

## Rules
- One card per event, never batch
- Provider name bold and first
- Relative times ("5m ago") not ISO
- Create threads on critical alerts
