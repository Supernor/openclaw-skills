---
name: github-guardian
description: Diagnose and repair GitHub authentication, credential helpers, and repo sync state. The go-to skill when any backup or push operation fails.
version: 2.0.0
author: repo-man
tags: [github, auth, repair, credential-helper, self-healing]
---

# github-guardian

## Purpose
Diagnose and fix GitHub connectivity problems — broken auth tokens, dead
credential helper paths, and repo sync drift. This is the repair skill
that other skills call when they encounter push failures. It follows a
non-destructive protocol: never force-push, never reset history, never
delete commits.

## When to use
- Any backup skill reports "push failed" or "authentication failed"
- `/repo-health` shows unreachable repos or HTTP 401
- After container rebuilds (credential helper paths change)
- After OpenClaw updates (image may have different binary locations)
- When `gh auth status` shows "not logged in"
- When `/key-drift-check` reports GH_TOKEN missing

## Invoke
```
/github-guardian
```

## Steps

### Phase 1: Preflight diagnosis

Collect the evidence first. Run ALL of these before attempting any fix.

```bash
# 1a. gh CLI exists and is functional
gh --version
```
- **If "command not found"**: gh CLI is not installed in the container. This is catastrophic for all GitHub operations.
  ERROR MEANING: The container image may have been rebuilt without gh. gh is installed at build time.
  HISTORY: This has never happened, but would require a Dockerfile fix (infra change — confirm with Robert).
  FIX: As root: `docker compose exec --user root openclaw-gateway sh -c "apt-get update && apt-get install -y gh"` (temporary — will vanish on next rebuild).

```bash
# 1b. Auth status
gh auth status 2>&1
```
- **If "Logged in to github.com"**: Auth is working. Problem is elsewhere.
- **If "not logged in"**: GH_TOKEN is missing or expired.
  ERROR MEANING: The GH_TOKEN env var is how gh authenticates. It's injected from /root/openclaw/.env via docker-compose env_file.
  FIX: Check inside container: `echo $GH_TOKEN | head -c 10` (should show `ghp_`). If empty, check docker-compose.override.yml has `env_file: [.env]`.

```bash
# 1c. Git credential helper
git config --global --get-all credential.https://github.com.helper
```
Required value: `!/home/node/.openclaw/scripts/gh auth git-credential`

- **If empty**: Credential helper was never set or got cleared.
- **If points to `/usr/bin/gh` or another path**: Dead path after container rebuild.
  ERROR MEANING: Git uses this helper to authenticate pushes. If it points to a binary that doesn't exist in the current container image, every `git push` fails with "authentication failed" — a misleading error that looks like a token problem but is actually a path problem.
  HISTORY: Broke on 2026-05-10 after v2026.5.8 update rebuilt the image. The gh binary moved paths.
  FIX: Set the correct helper (see Phase 2).

### Phase 2: Repair

Apply fixes based on Phase 1 findings. Minimum-change principle — fix only what's broken.

**Fix: Credential helper**
```bash
git config --global credential.https://github.com.helper '!/home/node/.openclaw/scripts/gh auth git-credential'
```

**Fix: GH_TOKEN missing in container**
This requires host-side action — the token comes from docker-compose env injection:
1. Verify on host: `grep GH_TOKEN /root/openclaw/.env` (should exist)
2. Verify override: `grep env_file /root/openclaw/docker-compose.override.yml` (should reference .env)
3. If both present, restart container to re-inject: `docker compose restart openclaw-gateway`

### Phase 3: Safety checks (history protection)

For each repo (`openclaw-config`, `openclaw-workspace`, `openclaw-skills`):
```bash
git -C /home/node/.openclaw/repos/<repo> status -sb
git -C /home/node/.openclaw/repos/<repo> rev-list --left-right --count origin/main...main
```

Interpret the rev-list output `L R`:
- `0 N` — local is N commits ahead. Safe to push.
- `N 0` — remote is N commits ahead. Do a `git pull --rebase` first.
- `N M` — DIVERGED. Pause and escalate with exact counts.

**Rules:**
- NEVER `git reset --hard` for sync recovery
- NEVER force-push backup history unless Robert explicitly approves
- Prefer `git push origin main` (simple push)
- If diverged: pause and escalate with the exact divergence counts and a proposed merge/rebase plan

### Phase 4: Verify repair

Test one repo push first, then apply fleet-wide.
```bash
# Pick one repo as canary
git -C /home/node/.openclaw/repos/openclaw-workspace push origin main 2>&1
```
- **If success**: Apply same fix to remaining repos.
- **If "authentication failed"**: Credential helper fix didn't take. Re-check Phase 1c.
- **If "rejected (non-fast-forward)"**: Diverged history. Go back to Phase 3.

Then verify all repos:
```bash
for repo in openclaw-config openclaw-workspace openclaw-skills; do
  echo "=== $repo ==="
  git -C "/home/node/.openclaw/repos/$repo" rev-parse main
  git -C "/home/node/.openclaw/repos/$repo" rev-parse origin/main
  git -C "/home/node/.openclaw/repos/$repo" status -sb
done
```
Success = local and remote SHAs match on `main`, and status shows no ahead/behind drift.

### Phase 5: Audit log
```bash
/home/node/.openclaw/scripts/log-event.sh INFO github-guardian "Repaired: <what was broken>. Verified: <evidence>"
```

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| "authentication failed" on push | Credential helper points to dead path | Set correct helper (Phase 2) |
| "not logged in" on gh auth | GH_TOKEN env var missing | Check env injection chain: .env -> compose -> container |
| One repo pushes, others don't | Per-repo credential or remote config issue | Check `git -C <repo> remote -v` — should point to `https://github.com/Supernor/<repo>.git` |
| Diverged history (both ahead AND behind) | Direct push to GitHub by another client | Escalate to Robert with counts. Do NOT force-push. |
| "could not read Password" prompt | Credential helper not returning token | Helper path wrong or gh not authenticated. Fix both. |
| gh works but git push doesn't | git and gh use different auth mechanisms | The credential helper bridges them. Re-set it (Phase 2). |

## Completion report

```
[Repo-Man] github-guardian: <PASS/PARTIAL/FAIL>
  Credential helper: <OK/FIXED/MISSING>
  Auth: <OK/FIXED/EXPIRED>
  Repo sync:
    openclaw-config: <OK/AHEAD N/DIVERGED>
    openclaw-workspace: <OK/AHEAD N/DIVERGED>
    openclaw-skills: <OK/AHEAD N/DIVERGED>
  Risk: <none / description of remaining issues>
```

## Related
- `/backup-suite` — calls this when any backup push fails
- `/repo-health` — detects the problems this skill fixes
- `/key-drift-check` — GH_TOKEN is one of the keys it monitors
- `/github-flight-recorder` — deeper forensics if guardian can't diagnose the issue
- `chart search "github auth"` — history of auth repairs
- `chart read learning-override-rollback-safety` — env var injection failures

## Notes
- This skill is referenced by nearly every other Repo-Man skill as the "fix auth" runbook. Keep it authoritative.
- The credential helper path `!/home/node/.openclaw/scripts/gh auth git-credential` is specific to this container layout. If container paths change (e.g., user changes from `node` to something else), this path must be updated everywhere.
- After container rebuilds, always run this skill as a preflight check before any backup operation.

Intent: Recoverable [I15], Secure [I16].
