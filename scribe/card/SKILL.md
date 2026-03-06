---
name: card
description: Last Run Summary card for a project channel. Shows reactor task results + project health + known issues. Usage: /card [channel]
version: 1.0.0
author: scribe
tags: [card, summary, reactor, status, project]
---

# card

## Invoke

```
/card                     # Card for current channel (uses channel context)
/card <channel-name>      # Card for a specific project channel
```

## What It Shows

A single-glance summary card combining:
1. **Last reactor task** for the channel (or system-wide if no channel match)
2. **Project health** (decisions + tasks snapshot)
3. **Known issues** (when any are open)

## Steps

### 1. Resolve channel (deterministic)

- If no argument: use current channel ID from message context (default)
- If `<#channel-id>`: extract numeric ID, validate 17-20 digit snowflake
- If `<channel-name>`: resolve to channel ID via project metadata
- If resolution fails: return deterministic error — "No channel found for **<input>**"
- **Always respond in current channel** regardless of target

### 2. Get reactor summary

Run from host (or via docker exec):
```bash
/root/.openclaw/scripts/project-card.sh <channel-id>
```

Or for current channel default:
```bash
/root/.openclaw/scripts/project-card.sh --current
```

The script returns a JSON payload with type `"project-card"`.

### 3. Format for Discord

Render the JSON payload as a Discord embed:

```
**[subject]** — [statusEmoji] [status]
_[completedAt] · [duration] · [toolCount] tools_

**Purpose:** [summary first line or subject]

**Wins:** [retro.wins or "—"]
**Losses:** [retro.losses or "—"]
**Learnings:** [retro.learnings or "—"]

**Project:** [project.decisionsResolved]/[project.decisionsTotal] decisions · [project.tasksDone]/[project.tasksTotal] tasks
**Next:** [nextAction or project recommendation]

[if knownIssues.openCount > 0]
**Known Issues ([openCount]):** [items summary]
[end if]
```

### 4. Return

Return formatted card to Captain for Relay rendering. Keep it compact — this is a glance card, not a full report.

## Error Handling

| Condition | Response |
|-----------|----------|
| Script exits non-zero / invalid JSON | "No card data available for this channel." |
| Both `reactor` and `project` are null | "No reactor tasks or project data found for this channel." |
| Channel resolution fails | "No channel found for **<input>**." |
| Invalid channel ID format | "Invalid channel reference." |

## Rules
- Read-only — never modify any state
- If no reactor task exists for the channel, show project-only data
- If no project data exists for the channel, show reactor-only data
- If neither exists, return "No data for this channel"
- Known issues block only appears when openCount > 0
- Use relative times ("2h ago") not ISO timestamps where possible
- **Always post result in the current channel** — even when querying a different channel
