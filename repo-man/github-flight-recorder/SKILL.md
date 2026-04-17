---
name: github-flight-recorder
description: GitHub incident forensics and evidence capture for Repo-Man. Use when backups fail, pushes stall, auth breaks, or GitHub activity looks wrong. Captures exact failing command, root cause class, and a safe fix path without rewriting history.
---

# github-flight-recorder

## Goal
Turn GitHub failures into fast, repeatable diagnosis with evidence-first fixes.

## Incident taxonomy
Classify first:
1. `auth` — bad token/session/scope
2. `helper-path` — git credential helper points to missing binary
3. `network` — DNS/TLS/connectivity issues
4. `remote-reject` — permissions/protection rejection
5. `history-state` — ahead/behind/diverged state conflict

## Evidence bundle (collect in this order)
```bash
date -u
whoami
which gh || true
gh auth status || true
git config --global --get-all credential.https://github.com.helper || true
git -C /home/node/.openclaw/repos/openclaw-workspace status -sb
git -C /home/node/.openclaw/repos/openclaw-skills status -sb
git -C /home/node/.openclaw/repos/openclaw-workspace remote -v
git -C /home/node/.openclaw/repos/openclaw-skills remote -v
```

If push fails, preserve the exact stderr line in the report.

## Fix policy
- Apply minimum-change fix for the detected class.
- Re-test with one repo first, then apply fleet-wide.
- No destructive history edits unless explicitly approved.

## Verification
For each affected repo:
```bash
git -C <repo> push origin main
git -C <repo> status -sb
git -C <repo> rev-parse main
git -C <repo> rev-parse origin/main
```

## Report format
- Failure class
- Root cause
- Exact fix applied
- Verification evidence
- Residual risk

Intent: Truthful, auditable GitHub operations.
