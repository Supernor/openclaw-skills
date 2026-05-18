---
name: github-flight-recorder
description: GitHub incident forensics — structured evidence capture, root cause classification, and safe fix path for push failures, auth breaks, and repo state issues. Deeper than github-guardian.
version: 2.0.0
author: repo-man
tags: [github, forensics, incident, diagnosis, evidence]
---

# github-flight-recorder

## Purpose
Turn GitHub failures into structured incident reports with evidence-first
diagnosis. When `/github-guardian` can't fix a problem, this skill captures
the full state of the system, classifies the failure, and produces a fix
path that preserves history. Think of it as the "black box" recorder — it
captures everything needed to understand what went wrong.

## When to use
- `/github-guardian` ran but couldn't resolve the issue
- A push failure has an unknown root cause
- Repo history is in a confusing state (diverged, detached HEAD, missing refs)
- Robert asks "what happened?" about a GitHub incident
- Multiple backup failures in a row — need to understand the pattern

## Invoke
```
/github-flight-recorder
```

## Steps

### Phase 1: Classify the incident

Before collecting evidence, classify what you're dealing with. This determines which evidence matters most.

| Class | Trigger | Example |
|-------|---------|---------|
| `auth` | Bad token, expired session, wrong scope | `gh auth status` shows "not logged in" |
| `helper-path` | Git credential helper points to missing binary | Helper path references `/usr/bin/gh` but that doesn't exist |
| `network` | DNS/TLS/connectivity failure | Timeouts, EHOSTUNREACH, SSL errors |
| `remote-reject` | GitHub rejects the push (permissions, protection) | "remote: Permission denied", branch protection rules |
| `history-state` | Ahead/behind/diverged/detached HEAD | `rev-list` shows both local and remote ahead |

### Phase 2: Collect evidence bundle

Run ALL of these. Capture output for the incident report. Order matters — early commands may fail, and the failure itself is evidence.

```bash
# Environment
date -u
whoami
echo "Container: $(hostname)"

# gh CLI
which gh || echo "gh: NOT FOUND"
gh --version 2>&1 || echo "gh: VERSION FAILED"
gh auth status 2>&1 || echo "gh: AUTH FAILED"
echo "GH_TOKEN prefix: $(echo $GH_TOKEN | head -c 10)"

# Git credential helper
git config --global --get-all credential.https://github.com.helper || echo "helper: NOT SET"

# Repo state — each repo
for repo in openclaw-config openclaw-workspace openclaw-skills; do
  REPO_PATH="/home/node/.openclaw/repos/$repo"
  echo "=== $repo ==="
  if [ -d "$REPO_PATH/.git" ]; then
    git -C "$REPO_PATH" status -sb
    git -C "$REPO_PATH" remote -v
    git -C "$REPO_PATH" rev-list --left-right --count origin/main...main 2>&1 || echo "rev-list: FAILED"
    git -C "$REPO_PATH" log --oneline -3
  else
    echo "NOT A GIT REPO or MISSING"
  fi
done
```

**If push failed, capture the exact stderr:**
The stderr from the failing `git push` is the most important single piece of evidence. If the calling skill captured it, include it verbatim in the report.

### Phase 3: Diagnose

Map the evidence to the incident class:

**auth**
- `gh auth status` shows "not logged in" + GH_TOKEN is empty = env injection failure
- `gh auth status` shows "not logged in" + GH_TOKEN has value = token expired or revoked
- FIX: See `/github-guardian` Phase 2

**helper-path**
- Credential helper points to a path that doesn't exist: `ls -la <helper-path>`
- FIX: `git config --global credential.https://github.com.helper '!/home/node/.openclaw/scripts/gh auth git-credential'`
- HISTORY: Broke after v2026.5.8 update (2026-05-10). Fixed by setting correct path.

**network**
- DNS failures, TLS handshake failures, timeouts
- FIX: Retry in 5 minutes. If persistent, check VPS connectivity: `curl -sI https://github.com`
- ESCALATE: If VPS networking is down, this is a Hostinger issue — beyond our fix.

**remote-reject**
- "Permission denied" = token lacks push access to the repo
- Branch protection = someone enabled branch protection on a backup repo (shouldn't happen)
- FIX: Verify token scopes: `gh auth status`. Check repo settings on GitHub.

**history-state**
- Both sides of `rev-list` non-zero = diverged. Someone pushed directly to the GitHub repo.
- FIX: Do NOT force-push. Options: (a) `git pull --rebase` if safe, (b) escalate to Robert with exact divergence counts.
- Detached HEAD = a previous checkout went wrong. FIX: `git checkout main`

### Phase 4: Apply minimum-change fix

- Fix ONLY the classified root cause
- Test with ONE repo first (canary), then apply to all
- No destructive history edits unless Robert explicitly approves

```bash
# After fix — verify each repo
for repo in openclaw-config openclaw-workspace openclaw-skills; do
  git -C "/home/node/.openclaw/repos/$repo" push origin main 2>&1
  git -C "/home/node/.openclaw/repos/$repo" status -sb
  echo "local:  $(git -C "/home/node/.openclaw/repos/$repo" rev-parse main)"
  echo "remote: $(git -C "/home/node/.openclaw/repos/$repo" rev-parse origin/main)"
done
```

Success = local and remote SHAs match, status clean.

### Phase 5: Incident report

Produce a structured report:

```
[Repo-Man] Flight Recorder -- Incident Report
  Class: <auth|helper-path|network|remote-reject|history-state>
  Root cause: <one sentence>
  Fix applied: <what was changed>
  Verification: <evidence that fix worked>
  Residual risk: <none | description>
  Repos affected: <list>
  Duration: <time from detection to resolution>
```

Log it:
```bash
/home/node/.openclaw/scripts/log-event.sh WARN github-flight-recorder "Class: <class>. Cause: <cause>. Fix: <fix>. Verified: <yes/no>"
```

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Evidence bundle shows all repos missing | `/home/node/.openclaw/repos/` directory wiped | Re-run backup scripts — they re-clone on first run |
| Helper set correctly but push still fails | Token scopes insufficient | `gh auth status` shows scopes. Need `repo` scope for private repos. |
| One repo fixed, others still broken | Different root causes per repo | Classify each repo separately. Don't assume fleet-wide cause. |
| Fix worked but breaks again next day | Container restart clears the git config fix | Make the fix persistent: add to a startup script or fix the Dockerfile (confirm with Robert). |
| Diverged history on all three repos | Automated process pushed to GitHub directly | Find the source (GitHub Actions, another tool). Escalate to Robert. |

## Related
- `/github-guardian` — the first-line repair skill (try this BEFORE flight-recorder)
- `/repo-health` — detects the symptoms this skill investigates
- `/backup-suite` — the workflow that usually triggers incident investigation
- `/log-event` — where incident reports are logged
- `chart search "github incident"` — history of past incidents and resolutions
- `chart search "credential helper"` — credential helper repair history

## Notes
- This skill is the SECOND line of defense. Always try `/github-guardian` first — it handles the common cases. Flight-recorder is for when guardian fails or the problem is unusual.
- Evidence collection is non-destructive. Nothing in Phase 2 modifies state.
- The incident taxonomy is cumulative — chart new failure classes as you discover them via `chart add`.
- If you discover a new failure pattern, chart it immediately: `chart add "issue-github-<pattern>" "<description>" "issue" 0.9`

Intent: Truthful, auditable GitHub operations. Recoverable [I15].
