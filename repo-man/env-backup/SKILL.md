---
name: env-backup
description: Generate .env.template (names only) and push to openclaw-config. Runs env-backup.sh script.
version: 2.0.0
author: repo-man
tags: [backup, env, secrets, github]
---

# env-backup

## Invoke
```
/env-backup
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/env-backup.sh
```

### 2. Report result

Script outputs JSON with `status`, `key_count`, `pushed`.

- **PASS+pushed**: `[Repo-Man] env-backup ✅ Template updated (<N> keys). Pushed to openclaw-config.`
- **PASS+no changes**: `[Repo-Man] env-backup ✅ Template unchanged.`
- **FATAL**: Script detected values in template. `[Repo-Man] ⚠️ FATAL: env-backup aborted — possible secret leak. Manual review required.`

### 3. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO env-backup "PASS: N keys, pushed=true/false"
```

## Notes
- Script includes provider keys from runtime env vars (docker-compose injected)
- Has built-in safety check — aborts if any values leak into template
- Do NOT re-implement — always use the script

Intent: Recoverable [I15]. Purpose: [P-TBD].
