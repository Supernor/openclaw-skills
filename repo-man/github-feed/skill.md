---
name: github-feed
description: Post GitHub activity to #ops-github as compact cards grouped by repo. Internal skill for nightly cron.
version: 2.0.0
author: repo-man
tags: [github, notifications, internal, components]
---

# github-feed

## Purpose
Post recent GitHub activity across all 3 repos to **#ops-github** as compact, scannable cards.

## Registry

Read channel ID and repo names from `~/.openclaw/registry.json`:
```bash
CHANNEL=$(jq -r .discord.channels."ops-github" ~/.openclaw/registry.json)
OWNER=$(jq -r .github.owner ~/.openclaw/registry.json)
```

## Target
- **Channel:** `1477754638290649209` (#ops-github)

## Repos
- `openclaw-config`
- `openclaw-workspace`
- `openclaw-skills`

## Steps

### 1. Gather recent activity

```bash
CURSOR_FILE="/home/node/.openclaw/github-feed-cursor.txt"
# Cursor stores last check timestamp (ISO8601)
```

For each repo:
```bash
gh api repos/Supernor/<repo>/commits?since=<cursor>&per_page=10
gh api repos/Supernor/<repo>/issues?state=all&since=<cursor>&per_page=5
gh api repos/Supernor/<repo>/tags?per_page=3
```

### 2. Skip if no activity

If zero commits, issues, and tags across all repos since last check — don't post anything. No "nothing happened" messages.

### 3. Post one card per repo with activity

For each repo that has activity, send a container card:

```json
{
  "action": "send",
  "channel": "discord",
  "channelId": "1477754638290649209",
  "components": {
    "container": {
      "accentColor": 5814783
    },
    "text": "<formatted — see template>"
  }
}
```

**Template — commits only (most common):**
```
**openclaw-skills** — <N> commits
`c660400` racp-split.sh + updated audit skill
`08adcb4` RACP split: per-agent Discord references
`351cdc7` Scoped Context policy + workspace cleanup
```

**Template — with issues and/or tags:**
```
**openclaw-config** — <N> commits, <N> issues
`a1b2c3d` Nightly cron results
`d4e5f6g` Dashboard update

🔴 Opened #5 — Model quarantine: google/gemini-3-flash
🟢 Closed #4 — Model quarantine: anthropic/claude-sonnet
🏷️ config-2026-03-01-scoped-context
```

### 4. Formatting rules

- **Repo name bold, stats on same line** — `**openclaw-skills** — 3 commits`
- **Commits as `sha` + message** — short SHA (7 chars), one line per commit, max 8 commits then `+ N more`
- **Issues: emoji + status + number + title** — 🔴 opened, 🟢 closed
- **Tags: 🏷️ + name** — one line each
- **No links in the card** — GitHub webhooks to this channel already have links. These cards are the summary layer.
- **Blue accent always** — activity is informational

### 5. Update cursor

Write current timestamp to cursor file.

### 6. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO github-feed "Posted: <N> commits, <N> issues, <N> tags across <N> repos"
```
