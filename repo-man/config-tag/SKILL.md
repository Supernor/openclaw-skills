---
name: config-tag
description: Tag current config state in openclaw-config for versioned rollback. Runs config-tag.sh.
version: 1.0.0
author: repo-man
tags: [config, versioning, github]
---

# config-tag

## Invoke
```
/config-tag [label]
```

Examples:
- `/config-tag` → creates `config-2026-03-01-snapshot`
- `/config-tag pre-rotation` → creates `config-2026-03-01-pre-rotation`
- `/config-tag model-health-update` → creates `config-2026-03-01-model-health-update`

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/config-tag.sh [label]
```

### 2. Report
`[Repo-Man] config-tag ✅ Tagged: <tag> in openclaw-config`

## When to use
- Before any openclaw.json change
- After key rotation
- Before/after major infrastructure updates
- When Claude Code reports changes via CHANGELOG.md
