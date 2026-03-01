---
name: rotate-key
description: Guided key rotation. Updates /app/.env, syncs to GitHub Secrets, restarts gateway, and verifies. Invoke with /rotate <keyname>.
version: 1.0.0
author: repo-man
tags: [security, keys, rotation]
---

# rotate-key

## Invoke

```
/rotate <KEYNAME>
```

Example: `/rotate OPENCLAW_PROD_ANTHROPIC_KEY`

## Pre-flight

1. Confirm keyname is in canonical list. If not: WARN and ask Robert to confirm before proceeding.
2. Ask Robert for the new key value (do not echo it back, do not log it, do not store it anywhere except /app/.env and GH Secret)

## Steps

### 1. Backup current .env first
Run `env-backup` skill before making any changes. If env-backup fails: STOP, log ERROR, do not proceed.

### 2. Update /app/.env
```bash
sed -i "s|^<KEYNAME>=.*|<KEYNAME>=<new_value>|" /app/.env
grep -E "^<KEYNAME>=.+" /app/.env
```
If verification fails: log FATAL "Key not written correctly to .env", STOP.

### 3. Update GitHub Secret
```bash
gh secret set <KEYNAME> --body "<new_value>" --repo NowThatJustMakesSense/openclaw-config
```

### 4. Restart gateway
```bash
docker restart openclaw-openclaw-gateway-1
sleep 5
docker ps | grep openclaw-gateway
```

### 5. Verify gateway is healthy
### 6. Run key-drift-check
### 7. Run env-backup

## Completion Report

Success: `[Repo-Man] rotate-key COMPLETE. <KEYNAME> rotated. Gateway restarted. Drift check: ✅. GitHub Secret: ✅.`
Partial: `[Repo-Man] rotate-key PARTIAL. <KEYNAME> updated in .env. GitHub Secret update FAILED. Gateway: ✅. Manual GH Secret update required.`
Failed: `[Repo-Man] ⚠️ rotate-key FAILED at step <N>. Gateway may be affected. Check logs immediately.`
