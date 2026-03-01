---
name: changelog-post
description: Post infrastructure changes to #ops-changelog. Internal skill triggered after backups detect changes.
version: 1.0.0
author: repo-man
tags: [changelog, notifications, internal]
---

# changelog-post

## Purpose
Post new infrastructure changes to **#ops-changelog** when backup scripts detect modified files.

## Target Channel
**#ops-changelog** — Channel ID: `1477754637527290030`

## Steps

### 1. Check for new changes
Read the latest section from Captain's CHANGELOG.md:
```bash
cat /home/node/.openclaw/workspace/CHANGELOG.md
```

Compare against the cursor file:
```bash
CURSOR_FILE="/home/node/.openclaw/changelog-post-cursor.txt"
```
The cursor stores the last posted changelog heading (e.g., `## 2026-03-01 — Log Governance`).

### 2. Format new entries

For each new changelog section, format as:

```
📋 **<heading>**
<context line>

**Created:**
- <item>
- <item>

**Modified:**
- <item>

**By:** <author>
```

Keep it concise — link to full CHANGELOG.md for details.

### 3. Send to #ops-changelog
Send the formatted message to channel `1477754637527290030`.

### 4. Update cursor
Write the latest heading to the cursor file.

### 5. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO changelog-post "Posted changelog: <heading>"
```

## When to run
- After `ws-backup.sh` or `skills-backup.sh` completes and detects changes
- As the final step of nightly cron (after dashboard-update)
- On demand if changelog was updated manually

## Notes
- Only post NEW sections — never re-post old ones
- If no new sections, skip silently
- One message per changelog section (don't batch multiple into one)
