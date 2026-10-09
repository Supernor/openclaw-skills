---
name: skills-backup
description: Push all agent skills, hooks, and scripts to openclaw-skills repo. Auto-discovers all workspace directories.
version: 2.0.0
author: repo-man
tags: [backup, skills, github]
---

# skills-backup

## Purpose
Back up all agent skills, hooks, and custom scripts to GitHub. If the VPS
dies or we need to rebuild, this repo lets us restore all automation.

## When to use
- As part of `/backup-suite` (the coordinator skill runs this)
- After creating or modifying any skill
- After an OpenClaw update (new workspace dirs may appear for new agents)

## Invoke
```
/skills-backup
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/skills-backup.sh
```
The script auto-discovers ALL workspace*/skills/ directories. You don't need
to list agents manually — new agents are automatically included.

### 2. Interpret the JSON output

| status | pushed | Meaning | What to report |
|--------|--------|---------|---------------|
| PASS | true | Skills pushed to openclaw-skills | "skills-backup: pushed (sha)" |
| PASS | false | No changes since last backup | "skills-backup: unchanged" |
| ERROR | - | Push failed | See diagnosis below |

### 3. Error diagnosis

**"push failed" or "authentication failed"**
- Git auth is broken. Run `/github-guardian` to repair.
- The commit is saved locally — it won't be lost.

**"clone failed"**
- Network issue or repo doesn't exist on GitHub.
- CHECK: `gh repo view Supernor/openclaw-skills --json name`
- If repo missing: escalate to Robert.

**"Permission denied" on file copy**
- File ownership changed after a host-side edit (Edit tool runs as root,
  container runs as uid 1000).
- FIX: Report the exact path. On the host: `chown -R 1000:1000 <path>`

**Script produces no output**
- Script may have crashed before producing JSON.
- CHECK: Run the script again and look for stderr: `bash -x /home/node/.openclaw/scripts/skills-backup.sh 2>&1`

### 4. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO skills-backup "status: <PASS/ERROR>, pushed: <true/false>"
```

## What gets backed up (auto-discovered)
- All workspace*/skills/ directories (every agent's skills)
- Hooks (~/.openclaw/hooks/)
- Scripts (~/.openclaw/scripts/)
- Organized in GitHub by agent display name (from agent-roster.json)

## Related
- `/backup-suite` — runs this as part of the full backup workflow
- `/github-guardian` — fixes auth when push fails
- `/workspace-backup` — backs up workspace MD files (separate repo)
- `chart search "backup"` — operational knowledge

Intent: Recoverable [I15].
