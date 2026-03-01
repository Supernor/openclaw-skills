---
name: repo-health
description: Verify all 3 GitHub repos, check ages, secrets count. Runs repo-health.sh script.
version: 2.0.0
author: repo-man
tags: [health, github, monitoring]
---

# repo-health

## Invoke
```
/repo-health
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/repo-health.sh
```

### 2. Format dashboard

Script outputs JSON with repos array, secrets count, local log health.

Format as:
```
📊 Repo Health
  openclaw-config: ✅ reachable, last push: <date> (<N> days ago)
  openclaw-workspace: ✅ reachable, last push: <date>
  openclaw-skills: ✅ reachable, last push: <date>
  GitHub Secrets: ✅ 7/7 match
  Local log: ✅ <N> lines, <size>
```

Flag any `stale: true` repos (>7 days since push) with ⚠️.

### 3. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO repo-health "PASS/WARN: summary"
```

## Notes
- Do NOT re-implement — always use the script
- Stale repos may mean backup cron isn't running
