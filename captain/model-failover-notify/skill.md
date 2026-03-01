---
name: model-failover-notify
description: "[Internal] Read new model health notifications and send alerts to Robert via Discord"
version: 1.0.0
author: system
tags: [models, health, notifications, internal]
---

# model-failover-notify

**Internal skill — called by Repo-Man during heartbeat, not user-invocable.**

## Steps

### 1. Read cursor file

```bash
cat /home/node/.openclaw/model-health-notify-cursor.txt 2>/dev/null || echo "0"
```

The cursor is a line number (0-indexed) indicating the last notification that was sent.

### 2. Read notifications file

```bash
cat /home/node/.openclaw/model-health-notifications.jsonl
```

Count total lines. If total lines <= cursor, nothing new — exit silently.

### 3. Process new notifications

For each line after the cursor position:
- Parse the JSON notification
- Format for Discord:

**Failure:**
```
🚨 **Model Health Alert**
Provider: **<provider>**
Status: <status> — <reason>
<message>
```

**Recovery:**
```
✅ **Model Recovered**
Provider: **<provider>**
<message>
```

### 4. Check chain degradation

Read `/home/node/.openclaw/model-health.json`.

If `fallbackChain.quarantined` has 2+ entries:
```
⚠️ **Fallback Chain Degraded**
<N> of <total> models quarantined: <list>
Consider running `/model-clear` or adding emergency fallbacks.
```

### 5. Update cursor

Write the new line count to the cursor file:

```bash
echo "<new_count>" > /home/node/.openclaw/model-health-notify-cursor.txt
```

### 6. Send via Discord

Send the formatted messages to the Discord channel where Robert will see them.

## Notes
- This skill is read-heavy, write-light (only updates cursor).
- If notification file doesn't exist, exit silently — monitor hasn't run yet.
- Batch multiple notifications into one message if they occurred in the same poll cycle.
