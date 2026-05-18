---
name: log-decision
description: Append a timestamped decision to DECISIONS.md in openclaw-config and push to GitHub. Creates an immutable audit trail of infrastructure and operational decisions.
version: 2.0.0
author: repo-man
tags: [decisions, audit, github, immutable]
---

# log-decision

## Purpose
Log an infrastructure or operational decision to DECISIONS.md in the
openclaw-config repo and push it to GitHub. Decisions are immutable — once
pushed, they are never edited. If a decision is reversed, a NEW entry is
logged referencing the original. This creates a durable audit trail that
survives session boundaries and can be read by any agent or human.

## When to use
- Robert makes a policy, architecture, or configuration decision
- An agent makes a decision that affects system behavior and needs a record
- When `/decisions-digest.sh` output shows a gap — decisions happened but weren't logged
- After resolving an incident where the root cause decision should be documented

## Invoke
```
/decision <text>
```
Example: `/decision Switch NIM failover to Gemini Flash Lite — NIM free tier exhausted`

## Steps

### Phase 1: Format the entry

Structure the entry as follows (latest entries go at the TOP of the file):
```markdown
## [2026-05-18T14:30:00Z] -- <decision text>

**Logged by:** spec-github (Repo-Man)
**Status:** FINALIZED

---
```

### Phase 2: Prepend to DECISIONS.md

```bash
cd /home/node/.openclaw/repos/openclaw-config
git pull -q origin main 2>/dev/null || true
```

Prepend the new entry to DECISIONS.md (latest at top, NOT appended at bottom).
If the file doesn't exist, create it with a header:
```markdown
# DECISIONS.md -- Infrastructure and Operational Decisions
# Immutable log. Never edit entries. Reverse decisions by adding new entries.
```

### Phase 3: Commit and push

```bash
cd /home/node/.openclaw/repos/openclaw-config
git add DECISIONS.md
git commit -m "[decision] $(date -u +%Y-%m-%d) <short summary>"
git push origin main
```

### Phase 4: Confirm

Report to the caller:
```
[Repo-Man] Decision logged: "<decision text>" -- pushed to openclaw-config
```

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| "push failed" or "authentication failed" | Git auth broken | Run `/github-guardian` to repair, then retry push |
| "not a git repository" | Repo dir missing or corrupted | Delete and re-clone: `rm -rf /home/node/.openclaw/repos/openclaw-config && /home/node/.openclaw/scripts/env-backup.sh` (forces re-clone) |
| "merge conflict" on pull | Someone pushed directly to the repo | `git -C /home/node/.openclaw/repos/openclaw-config pull --rebase origin main`, then retry |
| Permission denied on DECISIONS.md | Host-side edit changed file ownership | On host: `chown -R 1000:1000 /root/.openclaw/repos/openclaw-config` |

**"push failed" deep dive**
- ERROR MEANING: Git cannot authenticate with GitHub. The decision is committed locally and NOT lost.
- HISTORY: Broke on 2026-05-10 after container rebuild. Fixed by `/github-guardian`.
- FIX: Run `/github-guardian`. Local commit will be included in the next successful push.

## Rules
- Decisions are NEVER deleted or modified after push. This is an append-only log.
- If Robert asks to "undo" a decision: log a NEW entry noting the reversal. Never edit the original.
- Keep decision text concise — one sentence explaining WHAT and WHY.
- Include context (e.g., which provider, which config key) so a cold reader understands.

## Related
- `/decisions-digest.sh` — reads DECISIONS.md to build a summary for session starts
- `/log-event` — for operational events (complementary; events are transient, decisions are permanent)
- `/config-tag` — tag config state around important decisions
- `chart search "decisions"` — operational knowledge about decision tracking

Intent: Informed [I18].
