---
name: send-discord
description: Send a message to a Discord channel from automation
tags: [discord, message, send, notify, channel]
---
# Send Discord
## When to use
When sending ops notifications, alerts, or cross-channel messages from automation or Claude Code bridge.
## Execution
1. Parse: channel ID and message content
2. Run: `bash ~/.openclaw/scripts/bridge.sh send-discord --channel "<channel-id>" --message "<text>"`
3. Confirm message posted
## Logging
- Log via log-event

Intent: Connected [I10]. Purpose: [P-TBD].
