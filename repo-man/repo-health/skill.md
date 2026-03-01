---
name: repo-health
description: Verify all 3 GitHub repos are reachable, check last commit age, and confirm secrets count matches canonical list. Runs nightly and on demand. Invoke with /repo-health.
version: 1.0.0
author: repo-man
tags: [health, github, monitoring]
---

# repo-health

## When It Runs

- Nightly cron at 03:00 UTC (after workspace-backup and env-backup)
- On demand: `/repo-health`

## Checks

### 1. Repo reachability (all 3)
```bash
for repo in openclaw-config openclaw-workspace openclaw-skills; do
  gh api repos/NowThatJustMakesSense/$repo --jq '.name + " | pushed: " + .pushed_at + " | private: " + (.private|tostring)'
  echo "Exit: $?"
done
```

For each repo:
- EXIT 0 → INFO reachable, log last push timestamp
- EXIT non-zero → ERROR unreachable, log full stderr

### 2. Last commit age check
If any repo has no commits in more than 7 days: log WARN "repo <name> has not been updated in X days — backup may not be running"

### 3. GitHub Secrets count
```bash
gh secret list --repo NowThatJustMakesSense/openclaw-config --json name --jq '.[].name' | sort
```
Compare against canonical key list (7 keys). Any mismatch → WARN with specifics.

### 4. Local log file health
```bash
LOG="/home/node/.openclaw/workspace-spec-github/logs/repo-man.log"
wc -l "$LOG"
ls -lh "$LOG"
```
Log size and line count. If log doesn't exist: WARN "local log file missing — log-event may not be running correctly"

## Output Summary

Update LAST_RUN.md with:
```markdown
## repo-health — [ISO8601]
| Check | Result |
|-------|--------|
| openclaw-config | ✅ reachable, last push: <date> |
| openclaw-workspace | ✅ reachable, last push: <date> |
| openclaw-skills | ✅ reachable, last push: <date> |
| GitHub Secrets | ✅ 7/7 match |
| Local log | ✅ exists, N lines |
```

Discord summary (always send on nightly run):
- All pass: `[Repo-Man] repo-health ✅ All systems nominal. 3/3 repos reachable. Secrets: 7/7.`
- Any fail: `[Repo-Man] repo-health ⚠️ Issues found: <summary>. Check LAST_RUN.md on GitHub.`
