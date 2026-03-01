---
name: changelog-post
description: Post infrastructure changes to #ops-changelog as styled cards. Internal skill triggered after backups detect changes.
version: 2.0.0
author: repo-man
tags: [changelog, notifications, internal, components]
---

# changelog-post

## Purpose
Post new infrastructure changes to **#ops-changelog** as visually distinct cards.

## Registry

Read channel ID from `~/.openclaw/registry.json`:
```bash
CHANNEL=$(jq -r .discord.channels."ops-changelog" ~/.openclaw/registry.json)
COLOR_BLUE=$(jq -r .discord.colors.blue ~/.openclaw/registry.json)
```

## Target
- **Channel:** `1477754637527290030` (#ops-changelog)

## Steps

### 1. Check for new changes

Read `~/.openclaw/docs/CHANGELOG.md` and compare against cursor:
```bash
CURSOR_FILE="/home/node/.openclaw/changelog-post-cursor.txt"
```
The cursor stores the last posted changelog heading.

### 2. Format as container card

For each new changelog section, send a blue container card:

```json
{
  "action": "send",
  "channel": "discord",
  "channelId": "1477754637527290030",
  "components": {
    "container": {
      "accentColor": 5814783
    },
    "text": "<formatted entry — see template>"
  }
}
```

**Template:**
```
**<heading>**
_<context line from changelog>_

**Created:** <count> files
<bulleted list — max 5 items, then "+ N more">

**Modified:** <count> files
<bulleted list — max 5 items, then "+ N more">

_By: <author> · <date>_
```

**Example:**
```
**Discord Ops Channels**
_All operational output was going to one Discord chat. Robert had no "glance" view._

**Created:** 5 channels, 4 skills
- #ops-dashboard, #ops-alerts, #ops-nightly, #ops-changelog, #ops-github
- dashboard-update, changelog-post, github-feed skills

**Modified:** 3 files
- Nightly cron → 2-phase pipeline
- Repo-Man AGENTS.md → Discord section
- Relay AGENTS.md → ops channel awareness

_By: Claude Code · 2026-03-01_
```

### 3. Rules

- **Blue accent always** — changelog is informational, not an alert
- **Summarize, don't dump** — max 5 bullet items per section, then "+ N more"
- **One card per changelog section** — don't batch multiple into one message
- **Context line matters** — the _italicized_ context explains WHY, not just what
- **Only post NEW sections** — never re-post old entries
- **Skip silently if no new entries**

### 4. Update cursor

Write the latest heading to the cursor file.

### 5. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO changelog-post "Posted: <heading>"
```
