---
name: github-feed
description: Post GitHub activity to #ops-github as compact cards grouped by repo. Includes upstream contribution monitoring. Internal skill for nightly cron.
version: 4.0.0
author: repo-man
tags: [github, notifications, internal, components]
---

# github-feed

## Purpose
Post recent GitHub activity across own repos and upstream contributions to **#ops-github**.

## Template
Read `~/.openclaw/templates/github-feed.txt` for all Discord card formats, colors, and truncation rules.

## Registry
```bash
CHANNEL=$(jq -r '.discord.channels."ops-github"' ~/.openclaw/registry.json)
OWNER=$(jq -r '.github.owner' ~/.openclaw/registry.json)
UPSTREAM_REPO=$(jq -r '.github.upstream.repo' ~/.openclaw/registry.json)
UPSTREAM_PR=$(jq -r '.github.upstream.pr' ~/.openclaw/registry.json)
UPSTREAM_DISCUSSION=$(jq -r '.github.upstream.discussion' ~/.openclaw/registry.json)
```

## Part 1: Own Repos

### Repos
`openclaw-config`, `openclaw-workspace`, `openclaw-skills`

### Steps
1. Read cursor: `/home/node/.openclaw/github-feed-cursor.txt`
2. For each repo, fetch commits/issues/tags since cursor via `gh api`
3. Skip if zero activity across all repos
4. Post one **blue** card (`5814783`) per repo with activity, using template format

## Part 2: Upstream Contributions

### Steps
1. Read cursor: `/home/node/.openclaw/upstream-feed-cursor.txt`
2. Check PR comments/reviews via `gh api repos/<UPSTREAM_REPO>/pulls/<PR>/comments` etc.
3. Check discussion replies via GraphQL
4. Post **yellow** card (`16776960`) per item with activity, using template format
5. Skip silently if no upstream activity

## Finalize
1. Update both cursor files with current timestamp
2. Log result:
```bash
/home/node/.openclaw/scripts/log-event.sh INFO github-feed "Posted: <N> own repo cards, <N> upstream cards"
```
