---
name: workspace-backup
description: Commit and push all workspace MD files to the openclaw-workspace GitHub repo. Runs nightly and on demand. Invoke with /ws-backup.
version: 1.0.0
author: repo-man
tags: [backup, workspace, github]
---

# workspace-backup

## When It Runs

- Nightly cron at 03:00 UTC
- End of session (session-wrap)
- On demand: `/ws-backup`

## What Gets Backed Up

All MD files from all active agent workspaces:

| Source | Destination in repo |
|--------|-------------------|
| `/home/node/.openclaw/workspace/*.md` | `workspace-main/` |
| `/home/node/.openclaw/workspace-spec-github/*.md` | `workspace-spec-github/` |

Skills folders are excluded (backed up separately via openclaw-skills repo).

## Steps

### 1. Ensure local clone exists
```bash
REPO_PATH="/home/node/.openclaw/workspace-spec-github/openclaw-workspace"

if [ ! -d "$REPO_PATH/.git" ]; then
  git clone https://github.com/NowThatJustMakesSense/openclaw-workspace.git "$REPO_PATH"
fi
```
Log any clone failure as ERROR and stop.

### 2. Copy workspace files into repo
```bash
# Main workspace
mkdir -p "$REPO_PATH/workspace-main"
cp /home/node/.openclaw/workspace/*.md "$REPO_PATH/workspace-main/" 2>&1

# Repo-Man workspace (exclude logs — logs are in openclaw-config)
mkdir -p "$REPO_PATH/workspace-spec-github"
cp /home/node/.openclaw/workspace-spec-github/*.md "$REPO_PATH/workspace-spec-github/" 2>/dev/null
```
Log any copy errors as WARN (non-blocking — continue with what we have).

### 3. Commit and push
```bash
cd "$REPO_PATH"
git add -A
git diff --cached --quiet && echo "NO_CHANGES" || git commit -m "[workspace-backup] $(date -u +%Y-%m-%dT%H:%M:%SZ) auto-backup"
git push origin main
```

Capture exit codes at every step.

### 4. Log result

**No changes:**
- log-event: INFO "workspace-backup: no changes to commit"

**Changes committed and pushed:**
- log-event: INFO "workspace-backup: PASS. N files committed. SHA: <git rev-parse HEAD>"

**Push failed:**
- log-event: ERROR with full stderr
- Discord: `[Repo-Man] ERROR: workspace-backup push failed. Check GitHub auth or branch protection.`

**Clone failed:**
- log-event: FATAL with full stderr
- Discord: `[Repo-Man] ⚠️ FATAL: workspace-backup cannot clone openclaw-workspace repo. Manual check required.`
