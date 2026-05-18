---
name: github-feed
description: Post GitHub activity to Discord #ops-github as compact cards grouped by repo. Covers own repos and upstream contributions. Internal skill for nightly cron.
version: 5.0.0
author: repo-man
tags: [github, notifications, discord, cron, upstream]
---

# github-feed

## Purpose
Collect recent GitHub activity across our repos and upstream contributions,
then post formatted cards to Discord #ops-github. This is how Robert sees
what changed on GitHub without checking each repo manually. Uses cursor-based
delta detection so it only reports NEW activity since the last run.

## When to use
- Nightly agent dispatch (spec-github schedule slot 04:30-04:45 UTC) — include as part of nightly task
- When Robert asks "what happened on GitHub?"
- After a burst of commits or upstream PR activity
- Can be run manually via `/github-feed` for immediate status

## Steps

### Phase 1: Load registry

Read configuration from registry.json — do NOT hardcode channel IDs, repo names, or PR numbers.

```bash
CHANNEL=$(jq -r '.discord.channels."ops-github"' ~/.openclaw/registry.json)
OWNER=$(jq -r '.github.owner' ~/.openclaw/registry.json)
UPSTREAM_REPO=$(jq -r '.github.upstream.repo' ~/.openclaw/registry.json)
UPSTREAM_PR=$(jq -r '.github.upstream.pr' ~/.openclaw/registry.json)
UPSTREAM_DISCUSSION=$(jq -r '.github.upstream.discussion' ~/.openclaw/registry.json)
```

- **If registry.json missing**: STOP. This file is essential. Log ERROR and escalate.
  ERROR MEANING: The registry is the source of truth for all external IDs. Without it, you'll post to wrong channels or query wrong repos.
  FIX: Check `/home/node/.openclaw/registry.json` exists. If missing after container rebuild, restore from workspace backup.

### Phase 2: Own repos — activity scan

Read cursor from `/home/node/.openclaw/github-feed-cursor.txt` (ISO8601 timestamp of last run).

For each repo (`openclaw-config`, `openclaw-workspace`, `openclaw-skills`):
1. Fetch commits since cursor: `gh api repos/<OWNER>/<repo>/commits --jq "[.[] | select(.commit.committer.date > \"<cursor>\")]"`
2. Fetch issues/tags since cursor via `gh api`
3. Skip repos with zero activity

Post one **blue** card (`5814783` accent color) per repo with activity:
```
**<repo>** -- 3 new commits
  abc1234 Fix backup path
  def5678 Update DECISIONS.md
  ghi9012 Add key-drift canonical list

-> https://github.com/<OWNER>/<repo>
```

Read `~/.openclaw/templates/github-feed.txt` for exact Discord card formats, colors, and truncation rules.

### Phase 3: Upstream contributions — activity scan

Read cursor from `/home/node/.openclaw/upstream-feed-cursor.txt`.

1. Check PR comments/reviews: `gh api repos/<UPSTREAM_REPO>/pulls/<PR>/comments`
2. Check discussion replies via GraphQL
3. Post **yellow** card (`16776960` accent color) per item with activity
4. Skip silently if no upstream activity

### Phase 4: Finalize

1. Update both cursor files with current timestamp
2. Log result:
```bash
/home/node/.openclaw/scripts/log-event.sh INFO github-feed "Posted: <N> own repo cards, <N> upstream cards"
```

### Phase 5: Skip behavior
If zero activity across ALL repos and upstream — post nothing. Silent skip is correct behavior. Do NOT post "nothing happened" cards.

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| "registry.json not found" | File missing after container rebuild | Restore from workspace backup or recreate from charts |
| gh api returns 401 | GH_TOKEN expired or missing | Run `/github-guardian` to repair auth |
| gh api returns 403 rate limit | Too many API calls — hit GitHub rate limit | Wait 60 minutes. Consider reducing scan frequency. |
| Cards post to wrong channel | Channel ID stale in registry.json | Verify channel ID: check Discord, update registry.json |
| Cursor file missing | First run or file deleted | Script handles this — defaults to epoch. All recent activity will be posted (may be noisy on first run). |
| GraphQL query fails for discussion | Discussion number changed or repo moved | Check `UPSTREAM_DISCUSSION` in registry.json matches current discussion number |
| Duplicate cards posted | Cursor not updated after last run (crash mid-execution) | Manually update cursor file to current time: `date -u +%Y-%m-%dT%H:%M:%SZ > ~/.openclaw/github-feed-cursor.txt` |

**Rate limit deep dive**
- ERROR MEANING: GitHub API limits are 5000 requests/hour for authenticated users. This skill makes ~10 API calls per run, so hitting the limit means something ELSE is burning through the quota.
- HISTORY: Not hit yet as of 2026-05-18, but a likely risk if multiple skills poll GitHub concurrently.
- FIX: Check rate limit: `gh api rate_limit --jq '.rate'`. Identify the consumer. Space out cron schedules.

## Related
- `/upstream-check` — faster single-check version (this skill includes upstream but runs less frequently)
- `/log-event` — logs the result of each feed run
- `chart search "github feed"` — operational knowledge about feed formatting
- `chart search "discord channels"` — channel ID registry

## Notes
- Card formatting rules live in `~/.openclaw/templates/github-feed.txt` — read that file for color codes, truncation limits, and card structure. Do NOT hardcode formatting.
- Cursor files are the deduplication mechanism. If you reset a cursor, the next run will re-post everything since epoch. Only reset intentionally.
- This skill is the NIGHTLY version. For on-demand upstream checks, use `/upstream-check` instead.

Intent: Informed [I18].
