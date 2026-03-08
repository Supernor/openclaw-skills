---
name: skills-backup
description: Push all skills, hooks, and scripts to openclaw-skills repo. Runs skills-backup.sh script.
version: 1.0.0
author: repo-man
tags: [backup, skills, github]
---

# skills-backup

## Invoke
```
/skills-backup
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/skills-backup.sh
```

### 2. Report result

- **Pushed**: `[Repo-Man] skills-backup ✅ Pushed to openclaw-skills (<sha>).`
- **No changes**: `[Repo-Man] skills-backup ✅ No changes.`
- **Error**: Log and report failure.

## What gets backed up
- Captain workspace skills (model-status, model-clear, etc.)
- Repo-Man workspace skills (key-drift-check, error-report, etc.)
- Quartermaster workspace skills (decide, audit, etc.)
- Hooks (~/.openclaw/hooks/)
- Scripts (~/.openclaw/scripts/)

Intent: Recoverable [I15]. Purpose: [P-TBD].
