---
name: send-discord
description: Send messages to Discord channels from Claude Code without webhooks
tags: [discord, messaging, notification]
version: 1.0.0
---

# Send Discord

Send messages to Discord from Claude Code using OpenClaw's native messaging (no webhook needed).

## When to use
- Notify Robert of completed work
- Post status updates to ops channels
- Send results to project channels

## Commands

### Send a text message
```bash
oc message send --channel discord --target <channel-id> -m "message text"
```

### Send silently (no notification sound)
```bash
oc message send --channel discord --target <channel-id> -m "message" --silent
```

### Send with media
```bash
oc message send --channel discord --target <channel-id> -m "caption" --media /path/to/file.png
```

### Known channel IDs
Discover dynamically: `oc channels resolve discord <channel-name>`

Or from memory:
- Robert's DM: 187662930794381312
- #ops-dashboard: 1477754431780028598
- #ops-alerts: 1477754571697688627
- #ops-changelog: 1477754637527290030

## Rules
- Prefer `--silent` for non-urgent updates
- Keep messages concise — these go to a real person's phone
- For bulk status, use #ops-changelog not Robert's DM
- This is for outbound messages only — agents handle inbound via their normal flow
