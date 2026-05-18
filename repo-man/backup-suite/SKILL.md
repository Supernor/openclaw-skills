---
name: backup-suite
description: Run all GitHub backups, verify results, diagnose failures, fix or escalate. This is the primary backup skill — it coordinates env-backup, skills-backup, workspace-backup, and repo-health into one autonomous workflow.
version: 1.0.0
author: repo-man
tags: [backup, github, nightly, autonomous, self-healing]
---

# backup-suite

## Purpose

Run the full GitHub backup suite, verify every result, and handle failures
autonomously. This skill is designed so Repo-Man can own backups end-to-end
without human intervention for common failures.

## When to use

- Nightly cron dispatches this skill (primary use)
- After OpenClaw updates (backups may break due to path changes)
- When Robert reports backup errors in Discord #ops-github
- When repo-health shows stale repos (>7 days since push)
- When you see "push failed" in any backup log

## Architecture you need to understand

### Three backup scripts, three GitHub repos

| Script | What it backs up | GitHub repo | Runs where |
|--------|-----------------|-------------|------------|
| `env-backup.sh` | .env key names (NEVER values) | Supernor/openclaw-config (private) | Inside container |
| `skills-backup.sh` | All agent skills + hooks + scripts | Supernor/openclaw-skills (public) | Inside container |
| `ws-backup.sh` | All workspace MD files + memory | Supernor/openclaw-workspace (public) | Inside container |

### Nightly LOCAL backup (separate system, do not confuse)

The host-side cron at 3am UTC runs `nightly-backup.sh` which backs up SQLite
databases and config files LOCALLY to `/root/.openclaw/backups/`. This is NOT a
GitHub push — it's local file copies with 7-day retention. That script works
independently and is not part of this skill.

### GitHub authentication

All three scripts use `gh` CLI auth via GH_TOKEN environment variable.
The credential helper is configured at:
`credential.https://github.com.helper=!/home/node/.openclaw/scripts/gh auth git-credential`

If auth breaks, the github-guardian skill has the full repair runbook.

### Charts for deeper context
```
chart search "backup"              # All backup-related charts
chart read procedure-discord-plugin-update  # If Discord reporting is broken
chart read issue-engine-trust-dead-20260518 # Example of a broken tracking system
```

## Steps

### Phase 1: Preflight

Before running any backup, verify the prerequisites. If preflight fails,
skip to Phase 4 (Escalate) — don't run backups against broken infrastructure.

```bash
# 1a. GitHub auth
gh auth status 2>&1
```
- **If "not logged in"**: Auth is broken. Run `/github-guardian` to repair.
  ERROR MEANING: GH_TOKEN env var is missing or expired. The token comes from
  /root/openclaw/.env via docker-compose. If the container was rebuilt without
  env_file in the override, tokens won't be injected.
  HISTORY: This broke on 2026-05-10 when the override lost env_file during update.
  FIX: Verify `echo $GH_TOKEN` returns a value inside the container. If empty,
  check docker-compose.override.yml for env_file entry.

```bash
# 1b. Git credential helper
git config --global credential.https://github.com.helper 2>&1
```
- **If empty or points to dead path**: Run `/github-guardian` to repair.
  ERROR MEANING: The git credential helper tells git how to authenticate with
  GitHub. If it points to a binary that doesn't exist in the container (common
  after image rebuilds), every git push will fail with "authentication failed."
  FIX: Set it to `!/home/node/.openclaw/scripts/gh auth git-credential`

```bash
# 1c. Repos reachable
for repo in openclaw-config openclaw-skills openclaw-workspace; do
  gh repo view "Supernor/$repo" --json name 2>&1 | head -1
done
```
- **If "not found"**: Repo doesn't exist or token lacks access. Escalate to Robert.
- **If "HTTP 401"**: Token expired. Run `/github-guardian`.

### Phase 2: Run backups

Run each backup script. Capture the JSON output. Do NOT re-implement the
backup logic — always use the scripts. They handle cloning, diffing, committing,
and pushing. Your job is to interpret the results.

```bash
# 2a. Environment keys backup
RESULT_ENV=$(/home/node/.openclaw/scripts/env-backup.sh 2>&1)
echo "$RESULT_ENV"
```

Interpret the JSON:
- `"status":"PASS","pushed":true` — Success, template updated
- `"status":"PASS","pushed":false` — Success, no changes needed
- `"status":"FATAL"` — ABORT. Possible secret leak. Do NOT retry.
  WHAT THIS MEANS: The safety check found actual values (not just key names)
  in the template. This would push secrets to GitHub. The script correctly
  aborted. Escalate to Robert IMMEDIATELY with the exact error message.
  NEVER attempt to work around this safety check.
- `"status":"ERROR","message":"env file not found"` — The .env file path is
  wrong. Default is /app/.env. Check if the file exists. After OpenClaw updates,
  the path may change.
- `"status":"ERROR","message":"Commit succeeded but push failed"` — Git auth
  issue. Run `/github-guardian` to diagnose. The commit is saved locally and
  will be included in the next successful push.

```bash
# 2b. Skills backup
RESULT_SKILLS=$(/home/node/.openclaw/scripts/skills-backup.sh 2>&1)
echo "$RESULT_SKILLS"
```

Interpret:
- `"status":"PASS","pushed":true` — Success
- `"status":"PASS","pushed":false` — No changes
- `"status":"ERROR"` — Check error message. Common causes:
  - "push failed" — Git auth issue, run `/github-guardian`
  - "clone failed" — Network issue or repo doesn't exist
  - Permission denied — File ownership issue in container
    FIX: Files may be owned by root after host-side edits.
    Report the specific path that failed.

```bash
# 2c. Workspace backup
RESULT_WS=$(/home/node/.openclaw/scripts/ws-backup.sh 2>&1)
echo "$RESULT_WS"
```

Same interpretation as skills-backup.

### Phase 3: Verify

After all three scripts run, verify the repos actually received the push.

```bash
# 3a. Repo freshness check
/home/node/.openclaw/scripts/repo-health.sh 2>&1
```

Interpret the JSON:
- All repos show `"stale": false` — Backups are current
- Any repo shows `"stale": true` (>7 days since push) — That backup is failing
  silently. Check the specific script's log output from Phase 2.

```bash
# 3b. Log the combined result
/home/node/.openclaw/scripts/log-event.sh INFO backup-suite \
  "env=$(echo $RESULT_ENV | python3 -c 'import sys,json; print(json.load(sys.stdin).get(\"status\",\"?\"))' 2>/dev/null) \
   skills=$(echo $RESULT_SKILLS | python3 -c 'import sys,json; print(json.load(sys.stdin).get(\"status\",\"?\"))' 2>/dev/null) \
   ws=$(echo $RESULT_WS | python3 -c 'import sys,json; print(json.load(sys.stdin).get(\"status\",\"?\"))' 2>/dev/null)"
```

### Phase 4: Report or Escalate

**If all three passed**: Post a green summary to Discord #ops-github.
```
[Repo-Man] Backup suite ✅
  env-backup: ✅ (<key_count> keys, pushed=<true/false>)
  skills-backup: ✅ (pushed=<true/false>)
  workspace-backup: ✅ (pushed=<true/false>)
  Repos: all fresh
```

**If any failed**: Post a yellow/red summary with diagnostic info.
```
[Repo-Man] Backup suite ⚠️ (<N> of 3 passed)
  env-backup: ❌ <error message>
  skills-backup: ✅
  workspace-backup: ❌ <error message>
  DIAGNOSIS: <what you found when investigating>
  ACTION TAKEN: <what you tried to fix it>
  ESCALATION: <what Robert needs to do, if anything>
```

**If FATAL (secret leak detected)**: Post a RED alert immediately.
```
[Repo-Man] 🔴 BACKUP ABORTED — env-backup detected possible secret leak.
  Script aborted safely. No secrets were pushed.
  Robert: manual review required. Check env-backup.sh output.
```

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| All three push-failed | Git auth broken | Run `/github-guardian` |
| One repo push-failed, others OK | That repo has a conflict | `cd <repo> && git status -sb && git pull --rebase` |
| "env file not found" | Container path changed after update | Check if /app/.env exists |
| Stale repo but script says PASS | Script ran but cron isn't scheduled | Check crontab for backup crons |
| Permission denied on file copy | Host-side edit changed ownership | `chown -R 1000:1000 /path/to/affected/dir` |
| "not a git repository" | Repo clone was deleted/corrupted | Delete the repo dir, script will re-clone |

## After an OpenClaw update

Updates can break backups in several ways:
1. Container paths change (env file, script locations)
2. Git credential helper path becomes invalid (new image, different binary locations)
3. File permissions change (rebuild resets ownership)
4. New workspace directories appear (new agents) — scripts auto-discover these

After any update, run this skill manually to verify all three backups work
before relying on the nightly cron.

Intent: Recoverable [I15].
