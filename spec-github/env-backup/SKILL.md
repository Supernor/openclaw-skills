---
name: env-backup
description: Generate .env.template (names only, NEVER values) and push to openclaw-config. Runs env-backup.sh script.
version: 3.0.0
author: repo-man
tags: [backup, env, secrets, github]
---

# env-backup

## Purpose
Back up environment variable KEY NAMES (never values) to GitHub so we can
recreate the .env file on a new server. The template shows what keys are
needed without exposing any secrets.

## When to use
- As part of `/backup-suite` (the coordinator skill runs this)
- After adding new API keys or provider tokens to .env
- After an OpenClaw update (new keys may have been added upstream)

## Invoke
```
/env-backup
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/env-backup.sh
```
Do NOT re-implement this logic. The script has a critical safety check that
prevents secret values from leaking to GitHub.

### 2. Interpret the JSON output

| status | pushed | Meaning | What to report |
|--------|--------|---------|---------------|
| PASS | true | Template updated and pushed | "env-backup: N keys backed up" |
| PASS | false | No changes since last backup | "env-backup: unchanged" |
| FATAL | - | **SECRET LEAK DETECTED** | STOP. Alert Robert immediately. Never retry. |
| ERROR | - | Script failed | Read the message field for diagnosis (see below) |

### 3. Error diagnosis

**"env file not found"**
- The .env file at /app/.env doesn't exist.
- CAUSE: Container paths changed after an OpenClaw update, or env_file missing from docker-compose.override.yml.
- CHECK: `ls -la /app/.env`
- HISTORY: This path has been stable since v2026.3. It broke once on 2026-05-10 when the override lost env_file.

**"Commit succeeded but push failed"**
- Git auth is broken. The commit is saved locally (not lost) and will be included in the next successful push.
- FIX: Run `/github-guardian` to repair Git authentication.
- COMMON CAUSE: GH_TOKEN env var missing after container rebuild. Check: `echo $GH_TOKEN | head -c 10` (should show `ghp_` prefix)

**"FATAL: Value found in template"**
- The safety check found actual secret values, not just key names.
- This is a CRITICAL safety feature. NEVER work around it. NEVER retry.
- ESCALATE: Tell Robert exactly what the script reported. Include the leaked_count from the JSON.

### 4. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO env-backup "status: <PASS/ERROR/FATAL>, keys: <N>"
```

## Related
- `/backup-suite` — runs this as part of the full backup workflow
- `/github-guardian` — fixes auth when push fails
- `/key-drift-check` — verifies all required keys are present (complementary check)
- `chart search "backup"` — all backup-related operational knowledge

Intent: Recoverable [I15].
