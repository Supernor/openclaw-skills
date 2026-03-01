---
name: changelog-post
description: Post infrastructure changes to #ops-changelog as styled cards. Internal skill triggered after backups detect changes.
version: 3.0.0
author: repo-man
tags: [changelog, notifications, internal, components]
---

# changelog-post

## Purpose
Post new infrastructure changes to **#ops-changelog** as blue accent cards.

## Template
Read `~/.openclaw/templates/changelog-post.txt` for Discord card format and rules.

## Registry
```bash
CHANNEL=$(jq -r '.discord.channels."ops-changelog"' ~/.openclaw/registry.json)
```

## Steps

### 1. Check for new changes
Read `~/.openclaw/docs/CHANGELOG.md`, compare against cursor:
```bash
CURSOR_FILE="/home/node/.openclaw/changelog-post-cursor.txt"
```

### 2. Format and post
For each new section, send a blue container card (accent `5814783`) using the template from `templates/changelog-post.txt`. One card per section.

### 3. Update cursor
Write the latest heading to cursor file.

### 4. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO changelog-post "Posted: <heading>"
```
