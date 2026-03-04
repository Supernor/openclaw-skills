---
name: github-feed
description: Post GitHub activity (commits, Issues, tags) to #ops-github. Internal skill for nightly cron.
version: 1.0.0
author: repo-man
tags: [github, notifications, internal]
---

# github-feed

## Purpose
Post recent GitHub activity across all 3 repos to **#ops-github**.

## Target Channel
**#ops-github** — Channel ID: `1477754638290649209`

## Repos
- `openclaw-config`
- `openclaw-workspace`
- `openclaw-skills`

## Steps

### 1. Gather recent activity
For each repo, check commits since last post:

```bash
CURSOR_FILE="/home/node/.openclaw/github-feed-cursor.txt"
# Cursor stores last check timestamp (ISO8601)

# Recent commits
gh api repos/NowThatJustMakesSense/<repo>/commits?since=<cursor>&per_page=10

# Open issues
gh api repos/NowThatJustMakesSense/<repo>/issues?state=open&per_page=5

# Recent tags
gh api repos/NowThatJustMakesSense/<repo>/tags?per_page=3
```

### 2. Format activity feed

**Commits (grouped by repo):**
```
📦 **openclaw-skills** — 2 new commits
  `1974b00` [log-audit] Add log governance script + skill
  `a3f2b1c` [repo-man] Update AGENTS.md with log governance
```

**Issues (new/closed since last check):**
```
🔴 **Issue Opened:** #4 — Model quarantine: google/gemini-3-flash
🟢 **Issue Closed:** #3 — Model quarantine: anthropic/claude-sonnet
```

**Tags (new since last check):**
```
🏷️ **New tag:** config-2026-03-01-log-governance (openclaw-config)
```

### 3. Send to #ops-github
Send the formatted feed to channel `1477754638290649209`.

If no activity since last check, skip — don't send "no updates" messages.

### 4. Update cursor
Write current timestamp to cursor file.

### 5. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO github-feed "Posted: <N> commits, <N> issues, <N> tags"
```

## When to run
- As part of nightly cron (after backup scripts push changes)
- On demand for repo activity check

## Notes
- Only post if there IS activity — no empty updates
- Group commits by repo for readability
- Link to GitHub URLs when possible: `https://github.com/NowThatJustMakesSense/<repo>/commit/<sha>`
- Keep messages under 2000 chars — summarize if too many commits
