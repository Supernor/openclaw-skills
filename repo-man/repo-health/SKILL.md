---
name: repo-health
description: Verify all 3 GitHub backup repos are reachable, fresh, and secrets are intact. Diagnoses stale repos and auth failures.
version: 3.0.0
author: repo-man
tags: [health, github, monitoring, diagnosis]
---

# repo-health

## Purpose
Verify all three backup repos on GitHub are reachable and receiving pushes.
A stale repo means backups are silently failing — this skill catches that.

## When to use
- As part of `/backup-suite` Phase 3 (verification)
- When Robert reports backup errors in Discord #ops-github
- Session start preflight (SOUL.md says: verify gh auth, run key-drift-check)
- When any backup skill reports push failure

## Invoke
```
/repo-health
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/repo-health.sh
```

### 2. Interpret the JSON output

Format as dashboard:
```
Repo Health
  openclaw-config: [OK/STALE] reachable, last push: <date> (<N> days ago)
  openclaw-workspace: [OK/STALE] reachable, last push: <date>
  openclaw-skills: [OK/STALE] reachable, last push: <date>
  GitHub Secrets: [OK/DRIFT] <found>/<expected> match
```

Flag any `stale: true` repos (>7 days since push) — this means that repo's
backup skill is failing or not being scheduled.

### 3. Error diagnosis

**Repo shows "stale" (>7 days since push)**
- MEANING: The backup script for that repo hasn't successfully pushed in a week.
- CHECK: Run the specific backup skill manually:
  - openclaw-config stale → run `/env-backup`
  - openclaw-workspace stale → run `/workspace-backup`
  - openclaw-skills stale → run `/skills-backup`
- If the skill fails, check git auth with `/github-guardian`
- HISTORY: All three repos went stale after v2026.5.8 update (May 10) because
  container rebuild changed credential helper paths. Fixed by running github-guardian.

**Repo shows "unreachable"**
- MEANING: GitHub API returned an error for that repo.
- If HTTP 401: Token expired. Check `echo $GH_TOKEN | head -c 10` — should show `ghp_`
- If HTTP 404: Repo deleted or token lacks access. Escalate to Robert.
- If timeout: Network issue. Retry in a few minutes.

**Secrets count mismatch**
- MEANING: GitHub repo secrets don't match expected count.
- This is informational — secrets are managed by Robert, not by automation.
- Report the mismatch but don't attempt to fix.

### 4. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO repo-health "status: <summary>"
```

## Related
- `/backup-suite` — the coordinator that uses this for verification
- `/github-guardian` — fixes auth issues this skill detects
- `chart search "backup"` — operational knowledge

Intent: Observable [I13].
