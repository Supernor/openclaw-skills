---
name: key-drift-check
description: Compare environment keys against canonical list. Detects missing API keys, expired tokens, and unexpected additions.
version: 3.0.0
author: repo-man
tags: [security, keys, drift, preflight]
---

# key-drift-check

## Purpose
Verify all required API keys and tokens are present in the environment.
Missing keys cause agent failures — a missing NVIDIA_NIM_API_KEY crashed
the gateway on startup during the v2026.5.8 update (see learning-model-deprecation-fatal).

## When to use
- Session start (SOUL.md mandates this as part of bootstrap)
- Before running backup suite (auth depends on GH_TOKEN)
- After an OpenClaw update (new keys may be required, old ones may change names)
- When any agent reports authentication failures

## Invoke
```
/key-drift
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/key-drift-check.sh
```

### 2. Interpret the JSON output

| Field | Meaning |
|-------|---------|
| status | PASS or FAIL |
| found | Number of keys present |
| missing | Array of missing key names |
| extra | Array of unexpected key names (informational, not an error) |

- **PASS**: `[Repo-Man] key-drift: <found>/<total> keys present.`
  - If extras exist, list them as informational (new keys added but not in canonical list)
- **FAIL**: `[Repo-Man] key-drift: Missing: <names>. Action required.`

### 3. Error diagnosis

**Missing keys**
- MEANING: An API key that should be in the environment isn't there.
- COMMON CAUSES:
  - After container rebuild: env_file missing from docker-compose.override.yml
    (see learning-override-rollback-safety chart)
  - After key rotation: new key name not added to .env
  - After provider change: old key name removed but still referenced in openclaw.json
- FIX: Check /root/openclaw/.env on the host for the missing key name.
  If the key exists in .env but not in the container, the env_file injection is broken.
  Check: `docker compose config 2>/dev/null | grep <KEY_NAME>`
- ESCALATE: If the key is genuinely missing (not in .env either), Robert needs
  to add it. Tell him which key and which provider needs it.

**Extra keys (informational)**
- MEANING: Keys present that aren't in the canonical list.
- This is usually fine — it means someone added a new API key but didn't update
  the canonical list. Note them but don't alert.

**Script exits with error**
- MEANING: The script itself failed to run.
- CHECK: `bash -x /home/node/.openclaw/scripts/key-drift-check.sh 2>&1` for debug output
- COMMON: /app/.env file missing (container path changed after update)

### 4. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO key-drift-check "status: <PASS/FAIL>, found: <N>, missing: <names>"
```

## Related
- `/env-backup` — backs up key NAMES to GitHub (complementary)
- `/github-guardian` — GH_TOKEN is one of the keys this checks
- `chart read learning-override-rollback-safety` — env var injection failures
- `chart read learning-file-permissions-container` — permission issues after host edits

Intent: Secure [I16].
