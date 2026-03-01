---
name: github-feed
description: Post GitHub activity to #ops-github as compact cards grouped by repo. Includes upstream contribution monitoring. Internal skill for nightly cron.
version: 3.0.0
author: repo-man
tags: [github, notifications, internal, components]
---

# github-feed

## Purpose
Post recent GitHub activity across all repos to **#ops-github** as compact, scannable cards. Also monitors upstream contributions (PRs, discussions) for replies.

## Registry

Read channel ID, repo names, and upstream tracking from `~/.openclaw/registry.json`:
```bash
CHANNEL=$(jq -r '.discord.channels."ops-github"' ~/.openclaw/registry.json)
OWNER=$(jq -r '.github.owner' ~/.openclaw/registry.json)
UPSTREAM_REPO=$(jq -r '.github.upstream.repo' ~/.openclaw/registry.json)
UPSTREAM_PR=$(jq -r '.github.upstream.pr' ~/.openclaw/registry.json)
UPSTREAM_DISCUSSION=$(jq -r '.github.upstream.discussion' ~/.openclaw/registry.json)
```

## Target
- **Channel:** #ops-github (from registry)

---

## Part 1: Own Repos

### Repos
- `openclaw-config`
- `openclaw-workspace`
- `openclaw-skills`

### Steps

#### 1. Gather recent activity

```bash
CURSOR_FILE="/home/node/.openclaw/github-feed-cursor.txt"
# Cursor stores last check timestamp (ISO8601)
```

For each repo:
```bash
gh api repos/<OWNER>/<repo>/commits?since=<cursor>&per_page=10
gh api repos/<OWNER>/<repo>/issues?state=all&since=<cursor>&per_page=5
gh api repos/<OWNER>/<repo>/tags?per_page=3
```

#### 2. Skip if no activity

If zero commits, issues, and tags across all repos since last check — don't post anything.

#### 3. Post one blue card per repo with activity

```json
{
  "action": "send",
  "channel": "discord",
  "channelId": "<from registry>",
  "components": {
    "container": { "accentColor": 5814783 },
    "text": "<formatted>"
  }
}
```

**Template — commits:**
```
**openclaw-skills** — 3 commits
`c660400` racp-split.sh + updated audit skill
`08adcb4` RACP split: per-agent Discord references
```

**Template — with issues/tags:**
```
**openclaw-config** — 2 commits, 1 issue
`a1b2c3d` Nightly cron results

🔴 Opened #5 — Model quarantine: google/gemini-3-flash
🏷️ config-2026-03-01-scoped-context
```

---

## Part 2: Upstream Contributions

Monitor our PRs and discussions on the upstream OpenClaw repo for new activity.

### Steps

#### 1. Check PR for new comments/reviews

```bash
UPSTREAM_CURSOR_FILE="/home/node/.openclaw/upstream-feed-cursor.txt"

# PR comments (reviews, inline comments, general comments)
gh api repos/<UPSTREAM_REPO>/pulls/<UPSTREAM_PR>/comments --jq '[.[] | select(.created_at > "<cursor>")] | length'
gh api repos/<UPSTREAM_REPO>/issues/<UPSTREAM_PR>/comments --jq '[.[] | select(.created_at > "<cursor>")] | length'

# PR reviews
gh api repos/<UPSTREAM_REPO>/pulls/<UPSTREAM_PR>/reviews --jq '[.[] | select(.submitted_at > "<cursor>")] | length'

# PR state changes
gh api repos/<UPSTREAM_REPO>/pulls/<UPSTREAM_PR> --jq '{state, merged, mergeable_state, review_comments, comments}'
```

#### 2. Check discussion for new replies

```bash
gh api graphql -f query='
{
  repository(owner: "openclaw", name: "openclaw") {
    discussion(number: <UPSTREAM_DISCUSSION>) {
      comments(last: 5) {
        nodes { author { login } createdAt bodyText }
      }
    }
  }
}'
```

Filter for comments newer than the cursor.

#### 3. Post upstream activity as a yellow card

Yellow accent = external / needs attention (not red since it's not a failure, not blue since it needs action).

```json
{
  "action": "send",
  "channel": "discord",
  "channelId": "<from registry>",
  "components": {
    "container": { "accentColor": 16776960 },
    "text": "<formatted>"
  }
}
```

**Template — PR activity:**
```
**upstream** openclaw/openclaw#30996
🔔 2 new comments, 1 review

**@maintainer** (review): "Looks good, minor suggestion on the..."
**@user123** (comment): "Have you considered adding..."

→ https://github.com/openclaw/openclaw/pull/30996
```

**Template — Discussion activity:**
```
**upstream** openclaw/openclaw#30991 (discussion)
🔔 1 new reply

**@contributor** "This is a great idea, we actually..."

→ https://github.com/openclaw/openclaw/discussions/30991
```

**Template — PR state change:**
```
**upstream** openclaw/openclaw#30996
✅ PR merged!

→ https://github.com/openclaw/openclaw/pull/30996
```

or:
```
**upstream** openclaw/openclaw#30996
🔄 Changes requested by @maintainer

→ https://github.com/openclaw/openclaw/pull/30996
```

#### 4. Truncation rules

- Max 3 comments shown per card, then `+ N more`
- Comment text truncated at 100 chars with `...`
- Author name always bold and first
- Always include the link at the bottom with `→`

#### 5. Skip if no upstream activity

No card if nothing new since cursor. Silent skip.

#### 6. Update cursor

Write current timestamp to upstream cursor file.

---

## Formatting rules (both parts)

- **Repo name bold, stats on same line**
- **Commits as `sha` + message** — short SHA, max 8 then `+ N more`
- **Issues: emoji + status + number + title** — 🔴 opened, 🟢 closed
- **Tags: 🏷️ + name**
- **Upstream comments: bold author + type + truncated text**
- **Blue accent for own repos** — informational
- **Yellow accent for upstream** — needs attention
- **Always include link for upstream cards**

## Update cursor

Write current timestamp to cursor file(s).

## Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO github-feed "Posted: <N> own repo cards, <N> upstream cards"
```
