---
name: workspace-backup
description: Commit and push all workspace MD files (AGENTS.md, SOUL.md, IDENTITY.md, memory, decisions). Auto-discovers all workspace directories.
version: 3.0.0
author: repo-man
tags: [backup, workspace, github]
---

# workspace-backup

## Purpose
Back up all agent workspace files (identity, instructions, memory) to GitHub.
These files define who each agent IS — losing them means losing agent
personality, learned preferences, and accumulated context.

## When to use
- As part of `/backup-suite` (the coordinator skill runs this)
- After modifying any agent's AGENTS.md, SOUL.md, IDENTITY.md, or MEMORY.md
- After an OpenClaw update (new workspace dirs may appear for new agents)

## Invoke
```
/ws-backup
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/ws-backup.sh
```
Auto-discovers ALL workspace*/ directories. New agents are included automatically.
Excludes skills/ (those go to openclaw-skills via `/skills-backup`).

### 2. Interpret the JSON output

| status | pushed | Meaning | What to report |
|--------|--------|---------|---------------|
| PASS | true | Workspace files pushed | "workspace-backup: pushed (sha), N changes" |
| PASS | false | No changes since last backup | "workspace-backup: unchanged" |
| ERROR | - | Push failed | See diagnosis below |

### 3. Error diagnosis

**"push failed"**
- Git auth is broken. Run `/github-guardian` to repair.
- Commit is saved locally — not lost.

**"Permission denied" on file read**
- Workspace file ownership changed after host-side edit.
- This happens when Claude Code or another root process edits workspace files.
- FIX: On host, run `chown -R 1000:1000 /root/.openclaw/workspace*`

**Repo diverged (local and remote have different histories)**
- Someone pushed directly to the GitHub repo, or a previous force-push
  created a divergence.
- DO NOT force-push. Run `/github-guardian` Phase 2 safety checks.
- Common fix: `git -C <repo> pull --rebase origin main` then retry push.

### 4. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO workspace-backup "status: <PASS/ERROR>, pushed: <true/false>"
```

## What gets backed up (auto-discovered)
- All workspace*/*.md files (AGENTS.md, SOUL.md, IDENTITY.md, MEMORY.md, etc.)
- memory/ subdirectories (agent memory files)
- decisions/ subdirectories (decision logs)
- Does NOT include skills/ — use `/skills-backup` for those

## Related
- `/backup-suite` — runs this as part of the full backup workflow
- `/skills-backup` — backs up skills (separate repo, separate concern)
- `/github-guardian` — fixes auth and sync issues
- `chart search "backup"` — operational knowledge

Intent: Recoverable [I15].
