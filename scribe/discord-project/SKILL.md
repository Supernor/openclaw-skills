---
name: discord-project
description: Create a new Discord project channel in the Projects category, initialize decision tracking, and add to gateway allowlist. Usage: /project <name>
version: 1.0.0
author: relay
tags: [project, discord, channel, management]
---

# project

## Invoke

```
/project voice-wake         # Creates #voice-wake in Projects category
/project relay-agent        # Creates #relay-agent in Projects category
```

## Prerequisites

- Discord bot must have **Manage Channels** permission on the server
- Read the global configuration from `/home/node/.openclaw/shared-config.json` to obtain the `guild_id` and `projects` category ID (`categories.projects`).

## Steps

### 1. Validate name

- Lowercase, hyphens only, no spaces
- Max 30 chars
- Must not already exist as a channel

### 2. Create Discord channel

Use the `message` tool with `action: "channel-create"` to create a text channel in the Projects category. 
Retrieve `guildId` from `discord.guild_id` and `categoryId` from `discord.categories.projects` in `/home/node/.openclaw/shared-config.json`.
Set `name` to the project name and `type` to `0` (text).

### 3. Initialize decision tracking

Create `decisions/<name>.md` in workspace:
```markdown
# Decisions — <name>

| # | Decision | Status | Why | Date |
|---|----------|--------|-----|------|
```

Create `projects/<name>.md` in workspace:
```markdown
# Project: <name>

**Created:** <YYYY-MM-DD>
**Status:** Active
**Scope:** <to be defined>

## Topic

<one-line description — set with /topic>

## Key Links

<none yet>
```

### 4. Update gateway allowlist

Add the new channel ID to `openclaw.json` under `channels.discord.guilds.<guild_id>.channels`:
```json
"<channel_id>": {}
```

Note: if `groupPolicy` is `allowlist` and guild-level users are set, the channel may already be accessible. Only patch config if the channel is being ignored.

### 5. Confirm

```
📁 Project **<name>** created!
Channel: #<name>
Decision tracker: initialized (0 decisions)
Topic: not set — use `/topic <description>` in the channel

Head to #<name> to start working.
```

## Rules

- Never create channels outside the Projects category
- Always initialize the decision tracker
- If bot can't create channels, fall back to manual instructions
- Log the project creation as a decision in the new channel: `#1 | Project created | DONE | — | <date>`

Intent: Competent [I03]. Purpose: [P-TBD].
