---
name: key-drift-check
description: Compare env keys against canonical list. Runs the key-drift-check.sh script and reports results.
version: 2.0.0
author: repo-man
tags: [security, keys, drift]
---

# key-drift-check

## Invoke
```
/key-drift
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/key-drift-check.sh
```

### 2. Interpret and report

The script outputs JSON with `status`, `found`, `missing`, `extra` fields.

- **PASS**: `[Repo-Man] key-drift ✅ 7/7 keys present.` + list any extras as informational
- **FAIL**: `[Repo-Man] key-drift ❌ Missing: <names>. Action required.` Then log via:
  ```bash
  /home/node/.openclaw/scripts/log-event.sh ERROR key-drift-check "Missing keys: <names>"
  ```

### 3. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO key-drift-check "PASS: 7/7 keys"
```

## Notes
- Script checks both /app/.env and runtime env vars (provider keys injected via docker-compose)
- Do NOT re-implement the check logic — always use the script

Intent: Secure [I16]. Purpose: [P-TBD].
