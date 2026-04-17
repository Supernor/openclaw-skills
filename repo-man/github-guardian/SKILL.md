---
name: github-guardian
description: GitHub reliability hardening and safe-sync protocol for Repo-Man. Use when fixing GitHub auth/helper failures, preventing backup drift, validating non-destructive pushes, or restoring push reliability after container/runtime changes.
---

# github-guardian

## Goal
Keep GitHub backup flow permanently healthy with a non-destructive, auditable protocol.

## Runbook

### 1) Preflight (must pass before sync)
```bash
gh --version
gh auth status
git config --global -l | grep '^credential\.'
```

Required helper:
- `credential.https://github.com.helper=!/home/node/.openclaw/scripts/gh auth git-credential`

If helper points to a dead path (example: `/usr/bin/gh`), fix it before any push.

### 2) Safety checks (history protection)
For each repo (`openclaw-config`, `openclaw-workspace`, `openclaw-skills`):
```bash
git -C <repo> status -sb
git -C <repo> rev-list --left-right --count origin/main...main
```

Rules:
- Never `reset --hard` for sync recovery.
- Never force-push backup history unless explicitly approved.
- Prefer plain `git push origin main`.

### 3) Recovery actions
- Auth/helper failure: repair credential helper, then retry push.
- Repo ahead local: push as-is (preserve snapshots).
- Repo diverged: pause and escalate with exact divergence counts and proposed merge/rebase plan.

### 4) Postflight verification
```bash
git -C <repo> rev-parse main
git -C <repo> rev-parse origin/main
git -C <repo> status -sb
```

Success = local and remote SHAs match on `main`, and status shows no ahead/behind drift.

### 5) Audit log
Record one-line summary via `log-event.sh`:
- what was broken
- what was changed
- evidence that sync is healthy

## Outputs
Produce compact status:
- Credential helper: OK/FAIL
- Auth: OK/FAIL
- Repo sync status (each repo)
- Risk notes (if any)

Intent: Recoverable [I15], Secure [I16].
