---
name: skill-audit
description: Audit all skills for broken dependencies, missing scripts, and orphan files.
version: 1.0.0
author: repo-man
tags: [ops, audit, internal]
---

# skill-audit

## Purpose
Verify integrity of the skill ecosystem. Scans all skill.md files for references to scripts, files, channels, cursors, and other skills. Reports anything missing or broken.

## When to run
- On `/skill-audit` command (user-invocable)
- After deploying new skills or scripts
- As part of monthly context-audit

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/skill-audit.sh
# or with full dependency details:
/home/node/.openclaw/scripts/skill-audit.sh --verbose
```

### 2. Format output

**If status is PASS:**
```
✅ **Skill Audit** — all clear
22 skills, 87 dependencies verified, 0 issues
3 orphan scripts (not referenced by any skill)
```

**If status is WARN:**
```
⚠️ **Skill Audit** — warnings found
22 skills, 87 dependencies, 2 warnings

⚠️ github-feed: `github-feed-cursor.txt` — cursor file not initialized
⚠️ rotate-key: `rotate-key.sh` — script exists but not executable

Orphan scripts: `racp-split.sh`, `registry.sh`, `bridge.sh`
```

**If status is FAIL:**
```
🔴 **Skill Audit** — missing dependencies
22 skills, 87 dependencies, 1 missing, 1 warning

❌ new-skill: `missing-script.sh` — script not found
⚠️ github-feed: `github-feed-cursor.txt` — cursor not initialized
```

### 3. Post location
- Direct reply when run via `/skill-audit`
- Blue card to #ops-nightly when run via cron

### 4. Orphan scripts
Scripts in `~/.openclaw/scripts/` not referenced by any skill. Not necessarily a problem — some are utility scripts called by other scripts, or used directly by agents. Just informational.

Intent: Coherent [I19]. Purpose: [P-TBD].
