---
name: upstream-check
description: Check upstream OpenClaw PR and discussion for new activity. Runs upstream-check.sh for fast delta detection with cursor-based tracking.
version: 2.0.0
author: repo-man
tags: [github, upstream, monitoring, pr, discussion]
---

# upstream-check

## Purpose
Quick check for new activity on our upstream contributions (PR and discussion
in the OpenClaw repo). Returns new comments, reviews, and state changes since
the last check. Faster than waiting for the nightly `/github-feed` — use this
when you want an immediate upstream status.

## When to use
- Robert asks "any news on the PR?" or "upstream status"
- Every 6 hours via heartbeat (if configured)
- After receiving a GitHub notification about upstream activity
- When `/github-feed` is too slow (nightly) and you want real-time info

## Invoke
```
/upstream-check
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/upstream-check.sh
```

For cron/heartbeat use (suppress output when nothing new):
```bash
/home/node/.openclaw/scripts/upstream-check.sh --quiet
```

### 2. Interpret the JSON output

Key fields in the response:

| Field | Type | Meaning |
|-------|------|---------|
| `hasActivity` | bool | Any new activity since last check |
| `pr.comments` | int | New comment count on the PR |
| `pr.reviews` | int | New review count |
| `pr.state` | string | Current PR state (open/closed/merged) |
| `pr.stateChanged` | bool | State changed since last check |
| `pr.details` | array | Last 3 new comments/reviews with author and body |
| `discussion.replies` | int | New discussion reply count |
| `discussion.details` | array | New reply details |
| `totalNew` | int | Sum of all new items |

### 3. Format and post (if activity detected)

**If `hasActivity` is true**, post a yellow card to #ops-github:
```json
{
  "action": "send",
  "channel": "discord",
  "channelId": "<ops-github from registry>",
  "components": {
    "container": { "accentColor": 16776960 },
    "text": "<formatted>"
  }
}
```

**New comments template:**
```
**upstream** openclaw/openclaw#30996
New activity: 2 comments, 1 review since last check

**@maintainer** (review): "Looks good, minor suggestion..."
**@user123** (comment): "Have you considered..."

-> https://github.com/openclaw/openclaw/pull/30996
```

**State change template:**
```
**upstream** openclaw/openclaw#30996
PR merged!

-> https://github.com/openclaw/openclaw/pull/30996
```

**Discussion reply template:**
```
**upstream** openclaw/openclaw#30991 (discussion)
1 new reply

**@contributor**: "This is a great idea..."

-> https://github.com/openclaw/openclaw/discussions/30991
```

### 4. Formatting rules
- Max 3 comments shown, then `+ N more`
- Comment text truncated at 100 chars with `...`
- Author name always bold and first
- Always include link at bottom with `->` prefix
- Yellow accent (`16776960`) for upstream cards

### 5. Skip if no activity
If `hasActivity` is false, skip silently. The script handles cursor updates internally.

### 6. Direct reply mode
When invoked directly via `/upstream-check` (not cron), reply to the user even if nothing new:
```
**Upstream Status** -- checked just now

**PR #30996** -- open (no new activity since 2h ago)
**Discussion #30991** -- no new replies

Last check: 2026-05-18T22:26:11Z
```

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `{"error":"registry.json not found"}` | Registry missing after rebuild | Restore from workspace backup. Check `/home/node/.openclaw/registry.json` |
| gh api returns 401 | GH_TOKEN expired | Run `/github-guardian` to repair auth |
| Script returns empty or malformed JSON | jq failed parsing API response | Run with `bash -x` for debug: `bash -x /home/node/.openclaw/scripts/upstream-check.sh 2>&1` |
| PR number or discussion number wrong | Upstream references changed | Update `github.upstream.pr` and `github.upstream.discussion` in registry.json |
| "hasActivity: true" but details are empty | API returned items but jq filter failed | Check the `last(3; .)` jq filter — if upstream returns fewer than 3 items, this may produce empty output. Not data loss — just display. |
| State shows "unknown" | PR API call failed silently | gh api may have timed out. Retry once. If persistent, check rate limits. |

**GraphQL discussion query failure**
- ERROR MEANING: The GraphQL query to fetch discussion replies failed. This is a separate API from REST and can fail independently.
- HISTORY: GraphQL requires different auth scopes than REST. If GH_TOKEN was regenerated with minimal scopes, discussion queries may fail while PR queries succeed.
- FIX: Verify token scopes: `gh auth status`. Discussion access needs `read:discussion` scope.

## Related
- `/github-feed` — nightly version that covers own repos AND upstream (this is the fast single-check version)
- `/github-guardian` — fixes auth issues detected by this skill
- `/log-event` — log results after each check
- `chart search "upstream"` — history of upstream contribution tracking

## Notes
- The script manages its own cursor files: `upstream-feed-cursor.txt` and `upstream-check-state.json`. Do not edit these manually unless debugging.
- PR and discussion numbers come from `registry.json`, NOT hardcoded. If the upstream PR changes, update the registry.
- The `--quiet` flag is designed for cron use — produces zero output when there's nothing new, so cron-alert wrappers won't fire false alarms.

Intent: Informed [I18].
