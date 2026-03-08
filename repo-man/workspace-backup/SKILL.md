---
name: workspace-backup
description: Commit and push all workspace MD files. Runs ws-backup.sh script.
version: 2.0.0
author: repo-man
tags: [backup, workspace, github]
---

# workspace-backup

## Invoke
```
/ws-backup
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/ws-backup.sh
```

### 2. Report result

Script outputs JSON with `status`, `pushed`, `sha`, `changes`.

- **Pushed**: `[Repo-Man] ws-backup ✅ Pushed to openclaw-workspace (<sha>). <changes>`
- **No changes**: `[Repo-Man] ws-backup ✅ No changes to commit.`
- **Error**: `[Repo-Man] ws-backup ❌ Push failed.` Then:
  ```bash
  /home/node/.openclaw/scripts/log-event.sh ERROR workspace-backup "Push failed: <stderr>"
  ```

### 3. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO workspace-backup "PASS: pushed=true/false"
```

## Notes
- Backs up ALL 4 workspaces (Captain, Relay, Repo-Man, Quartermaster)
- Includes memory/ and decisions/ subdirectories
- Excludes skills (separate repo — use /skills-backup)
- Do NOT re-implement — always use the script

Intent: Recoverable [I15]. Purpose: [P-TBD].
