---
name: rotate-key
description: Guided key rotation — updates /app/.env, syncs to GitHub Secrets, restarts gateway, and verifies. Safety-first with config tagging and env-backup bracketing the change.
version: 2.0.0
author: repo-man
tags: [security, keys, rotation, guided]
---

# rotate-key

## Purpose
Rotate an API key or token end-to-end: backup current state, update the
.env file, sync to GitHub Secrets, restart the gateway, and verify
everything works. This is a guided process — Robert provides the new key
value, the skill handles every other step.

## When to use
- Robert says "rotate <keyname>" or provides a new key value
- Key drift check reveals a compromised or expired key
- Provider sends a key expiry notice
- After a security incident where keys may be compromised

## Invoke
```
/rotate <KEYNAME>
```
Example: `/rotate OPENCLAW_PROD_ANTHROPIC_KEY`

## Steps

### Phase 1: Pre-flight safety

1. **Confirm key is known**: Check if KEYNAME is in the canonical key list (`/key-drift-check` output). If not: WARN Robert — unknown key, confirm before proceeding.
2. **Ask Robert for the new value**: Request the new key. NEVER echo it back, log it, or store it anywhere except /app/.env and GitHub Secret.
3. **Tag config**: Run `/config-tag pre-rotation` to snapshot current state.
   - If tag fails: STOP. You need a rollback point before changing anything.
4. **Backup current env**: Run `/env-backup` to capture the current key inventory.
   - If backup fails: STOP, log ERROR, do not proceed. The safety net must be in place.

### Phase 2: Apply the change

```bash
# Update .env — sed replaces the existing line
sed -i "s|^<KEYNAME>=.*|<KEYNAME>=<new_value>|" /app/.env
# Verify the write succeeded
grep -E "^<KEYNAME>=.+" /app/.env
```
- **If grep returns nothing**: Key was not written. Check if the key existed in .env at all — new keys need an `echo` append, not a `sed` replace.
  ERROR MEANING: sed only replaces existing lines. If the key doesn't already exist in .env, sed silently does nothing.
  FIX: Use `echo "<KEYNAME>=<value>" >> /app/.env` for new keys.
- **If grep succeeds**: Proceed.

### Phase 3: Sync to GitHub Secrets

```bash
gh secret set <KEYNAME> --body "<new_value>" --repo Supernor/openclaw-config
```
- **If "not found"**: Repo doesn't exist or token lacks admin access. Mark as PARTIAL and continue — the .env update is the critical path.
- **If "HTTP 401"**: GH_TOKEN can't set secrets. This may require Robert to update via GitHub UI.

### Phase 4: Restart and verify

```bash
# Restart gateway to pick up new key
docker restart openclaw-openclaw-gateway-1
sleep 5
docker ps | grep openclaw-gateway
```
- **If container shows "Up"**: Gateway restarted successfully.
- **If container shows "Exited" or "Restarting"**: The new key may be malformed or the wrong key was changed. Check logs: `docker logs openclaw-openclaw-gateway-1 --tail 20`. Consider rolling back to the pre-rotation tag.

### Phase 5: Post-rotation verification

1. **Run `/key-drift-check`**: Verify all keys are present including the rotated one.
2. **Run `/env-backup`**: Backup the new state to GitHub.
3. **Tag config**: Run `/config-tag post-rotation` to bookmark the new state.

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| sed does nothing (key not updated) | Key name doesn't exist in .env yet | Use `echo` append instead of sed replace |
| Gateway won't start after rotation | Malformed key value (extra whitespace, quotes) | Check `/app/.env` for formatting. Roll back: `git -C /home/node/.openclaw/repos/openclaw-config checkout <pre-rotation-tag>` |
| gh secret set fails with 403 | Token lacks admin scope on repo | Robert must set secret manually via GitHub UI |
| Key drift check fails after rotation | env_file not reloaded — container needs full recreate, not just restart | `docker compose down openclaw-gateway && docker compose up -d openclaw-gateway` |
| Gateway starts but provider calls fail | New key is valid format but wrong key (e.g., test key in prod) | Verify with Robert — check the key prefix matches the expected provider format |

## Completion report

**Success**: `[Repo-Man] rotate-key COMPLETE. <KEYNAME> rotated. Gateway restarted. Drift check: PASS. GitHub Secret: PASS.`
**Partial**: `[Repo-Man] rotate-key PARTIAL. <KEYNAME> updated in .env. GitHub Secret: FAILED (manual update needed). Gateway: OK.`
**Failed**: `[Repo-Man] rotate-key FAILED at Phase <N>. <reason>. Pre-rotation tag: <tag> available for rollback.`

## Related
- `/config-tag` — creates rollback snapshots before and after rotation
- `/env-backup` — captures key inventory before changes
- `/key-drift-check` — verifies all keys post-rotation
- `/github-guardian` — fixes auth if GH_TOKEN itself needs rotation
- `chart search "key rotation"` — past rotation events
- `chart read learning-override-rollback-safety` — env var injection issues

## Notes
- NEVER log, echo, or store key values anywhere other than /app/.env and GitHub Secrets.
- If GH_TOKEN itself is the key being rotated, you must update it in /root/openclaw/.env on the host AND restart the container — the token is injected via docker-compose env_file.
- Rotation is NOT atomic. If it fails partway, use the pre-rotation config tag to assess what state you're in.

Intent: Secure [I16].
