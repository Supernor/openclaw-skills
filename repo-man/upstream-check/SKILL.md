---
name: upstream-check
description: Check upstream PR and discussion for new activity. Faster than waiting for nightly github-feed.
version: 1.0.0
author: repo-man
tags: [github, upstream, monitoring]
---

# upstream-check

## Purpose
Quick check for new activity on our upstream contributions (PR #30996, Discussion #30991). Returns new comments, reviews, state changes since last check.

## When to run
- On `/upstream-check` command (user-invocable)
- Every 6 hours via heartbeat (if configured)
- After any upstream-related notification

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/upstream-check.sh
```

### 2. Format output

**If `hasActivity` is true**, post a yellow card:

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

**Template — new comments:**
```
**upstream** openclaw/openclaw#30996
🔔 2 new comments, 1 review since last check

**@maintainer** (review): "Looks good, minor suggestion..."
**@user123** (comment): "Have you considered..."

→ https://github.com/openclaw/openclaw/pull/30996
```

**Template — state change:**
```
**upstream** openclaw/openclaw#30996
✅ PR merged!

→ https://github.com/openclaw/openclaw/pull/30996
```

**Template — discussion reply:**
```
**upstream** openclaw/openclaw#30991 (discussion)
🔔 1 new reply

**@contributor**: "This is a great idea..."

→ https://github.com/openclaw/openclaw/discussions/30991
```

### 3. Formatting rules
- Max 3 comments shown, then `+ N more`
- Comment text truncated at 100 chars with `...`
- Author name always bold and first
- Always include link at bottom with `→`
- Yellow accent (16776960) — needs attention

### 4. Skip if no activity
If `hasActivity` is false, skip silently. The script handles cursor updates.

### 5. Direct reply mode
When run via `/upstream-check`, reply directly to the user instead of posting to #ops-github. Include all details even if no new activity:
```
**Upstream Status** — checked just now

**PR #30996** — open (no new activity since 2h ago)
**Discussion #30991** — no new replies

Last check: 2026-03-01T22:26:11Z
```

Intent: Informed [I18]. Purpose: [P-TBD].
