---
name: card
description: Project card — reactor task summary + project health + known issues. Relay executes directly (read-only, no routing needed).
version: 1.0.0
author: relay
tags: [card, summary, reactor, status, project, quick-look]
---

# card

## Invoke — User Forms

Relay intercepts these patterns and executes directly (no Captain routing):

| User says | Parsed as |
|-----------|-----------|
| `/card` | Card for **current channel** |
| `give me a /card for this project` | Card for **current channel** |
| `/card <#channel-id>` | Card for the **mentioned channel** |
| `/card <channel-name>` | Card for the **named channel** |
| `give me a /card for <#channel-id>` | Card for the **mentioned channel** |
| `give me a /card for <channel-name>` | Card for the **named channel** |

### Pattern Detection

Match any message containing `/card`. Then parse the target:

1. **No target** (bare `/card` or natural language without a channel ref) → use current channel ID from message context
2. **Discord mention** `<#1234567890>` → extract the numeric ID
3. **Channel name** (bare text after `/card`, e.g. `/card website-generator`) → resolve via `discord-scan.sh`

## Execution

### Step 1: Resolve target channel (deterministic)

```
FILLER = ["this project", "this channel", "here", "for me", "for this", "for us"]

IF message contains <#DIGITS>:
  CHANNEL_ID = extracted digits
  Validate: CHANNEL_ID must be 17-20 digits (Discord snowflake)
  IF invalid format:
    RESPOND: "Invalid channel reference. Use <#channel-id> or a channel name."
    STOP
  MODE = "channel"
ELIF message has text after /card that is NOT filler:
  CHANNEL_NAME = extracted text (trim, lowercase, strip #)
  MODE = "name"
ELSE:
  CHANNEL_ID = current channel ID from message context
  MODE = "channel"
```

Filler phrases to ignore: `this project`, `this channel`, `here`, `for me`, `for this`, `for us`.

**Default**: current channel. **Override**: explicit `<#channel-id>` or channel name. **Response**: always post in current channel regardless of target.

### Step 2: Call project-card.sh

Run via `exec` tool:

```bash
# Channel ID known:
bash ~/.openclaw/scripts/project-card.sh <channel-id>

# Channel name (no ID):
bash ~/.openclaw/scripts/project-card.sh --channel-name <channel-name>

# Current channel, no args:
bash ~/.openclaw/scripts/project-card.sh --current
```

The script returns JSON with `type: "project-card"`.

### Step 3: Handle errors (deterministic)

| Condition | Response (post in current channel) |
|-----------|-------------------------------------|
| Script exits non-zero or invalid JSON | "No card data available for this channel." |
| JSON has `reactor: null` AND `project: null` | "No reactor tasks or project data found for this channel." |
| Channel name resolution fails (no match) | "I couldn't find a channel called **<name>**. Check the name and try again." |
| Invalid `<#channel-id>` format | "Invalid channel reference. Use <#channel-id> or a channel name." |

Every error response is posted in the **current channel** — never silently fail.

### Step 4: Format for Discord

Render a compact embed in the current channel. Use the JSON fields:

```
**[reactor.subject or projectName]** — [statusEmoji] [reactor.status]
_[reactor.completedAt] · [reactor.duration] · [reactor.toolCount] tools_

**Wins:** [reactor.retro.wins or "—"]
**Losses:** [reactor.retro.losses or "—"]
**Learnings:** [reactor.retro.learnings or "—"]

**Project:** [project.decisions.resolved]/[project.decisions.total] decisions · [project.tasks.done]/[project.tasks.total] tasks
**Last activity:** [project.lastActivity]

[if knownIssues]
**Known Issues ([knownIssues.openCount]):** [items joined]
[end if]
```

Status emojis: `completed` → checkmark, `failed` → X, `timeout` → hourglass, `running` → gear.

If only reactor data exists (project is null), skip the Project line.
If only project data exists (reactor is null), skip reactor lines — show project health only.

## Channel Name Resolution

When the user passes a channel name (not an ID), resolve it:

```bash
bash ~/.openclaw/scripts/discord-scan.sh channel "<name>"
```

This returns channel metadata including the ID. Extract the ID and pass it to `project-card.sh`.

If no channel matches, respond: "I couldn't find a channel called **<name>**. Check the name and try again."

## Rules

- **Read-only** — never modify state
- **Relay executes this directly** — no Captain routing, no Scribe dispatch
- **Post in current channel** — always respond where Robert asked
- **Compact output** — this is a glance card, not a report
- **Graceful degradation** — show whatever data exists, skip what doesn't
