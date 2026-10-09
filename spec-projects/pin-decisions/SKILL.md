---
name: pin-decisions
description: Pin or update the consolidated decision board as a pinned message in the current Discord channel. Usage: /pin
version: 1.0.0
author: relay
tags: [decisions, project, discord, pin]
---

# pin-decisions

## Invoke

```
/pin                    # Pin/update decision board in current channel
```

## Steps

### 1. Generate decision board

Read `decisions/<channel-name>.md` and format the same way as `/decisions`.

### 2. Check for existing pinned decision board

Look at pinned messages in the current channel. If one starts with "📋 **Decision Board", that's the old one.

### 3. Post and pin

- Post the formatted decision board as a new message
- Pin it
- If an old pinned decision board exists, unpin it (don't delete — history is preserved in chat)

### 4. Confirm

React to the pinned message with 📌.

## Rules

- Only one decision board should be pinned at a time per channel
- If no decisions exist for this channel, reply "Nothing to pin — no decisions tracked yet."
- Include a footer: `Last updated: <YYYY-MM-DD HH:MM UTC>`

Intent: Informed [I18]. Purpose: [P-TBD].
