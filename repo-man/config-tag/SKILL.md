---
name: config-tag
description: Tag current config state in openclaw-config for versioned rollback. Runs config-tag.sh to create a named git tag before or after changes.
version: 2.0.0
author: repo-man
tags: [config, versioning, rollback, github, safety]
---

# config-tag

## Purpose
Create a named git tag in the openclaw-config repo so you can roll back to
a known-good configuration state. Every config change should be bracketed
by tags — one before (pre-) and one after (post-) — so recovery is a
one-command `git checkout <tag>`.

## When to use
- Before any openclaw.json change (tag as safety net)
- After key rotation (capture the post-rotation state)
- Before/after major infrastructure updates
- When another skill says "tag config first" (e.g., `/rotate-key` Phase 1)
- When Robert asks to snapshot the current config

## Invoke
```
/config-tag [label]
```

Examples:
- `/config-tag` creates `config-2026-05-18-snapshot`
- `/config-tag pre-rotation` creates `config-2026-05-18-pre-rotation`
- `/config-tag model-health-update` creates `config-2026-05-18-model-health-update`

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/config-tag.sh [label]
```
The script handles: pulling latest from remote, deduplicating tag names
(appends `-2`, `-3` etc. if a tag already exists for that date+label),
creating an annotated tag, and pushing it to GitHub.

### 2. Interpret the JSON output

| status | Meaning | What to report |
|--------|---------|---------------|
| PASS | Tag created and pushed | `[Repo-Man] config-tag: Tagged <tag> in openclaw-config` |

Expected output: `{"status":"PASS","tag":"config-2026-05-18-<label>","repo":"openclaw-config"}`

### 3. Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Script exits with "not a git repository" | Repo dir missing or corrupted | Delete `/home/node/.openclaw/repos/openclaw-config` and re-clone via `/backup-suite` |
| "push failed" or "authentication failed" | Git auth broken — GH_TOKEN missing or credential helper dead | Run `/github-guardian` to repair auth, then retry |
| "permission denied" on repo dir | Host-side edit changed ownership to root | On host: `chown -R 1000:1000 /root/.openclaw/repos/openclaw-config` |
| Tag created but push fails | Network issue or repo permissions | Tag exists locally — retry push with `git -C /home/node/.openclaw/repos/openclaw-config push origin <tag>` |

**"push failed" deep dive**
- ERROR MEANING: Git cannot authenticate with GitHub to push the tag.
- HISTORY: Broke on 2026-05-10 after container rebuild changed credential helper paths.
- FIX: Run `/github-guardian`. If that fails, check `echo $GH_TOKEN | head -c 10` inside container (should show `ghp_`).

### 4. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO config-tag "tag: <tag_name>"
```

## Related
- `/rotate-key` — calls this before rotation as a safety step
- `/env-backup` — backs up key names (complementary to config tagging)
- `/github-guardian` — fixes auth issues that block tag pushes
- `chart search "config versioning"` — operational knowledge about config management
- `chart search "rollback"` — past rollback events and procedures

## Notes
- Tags are lightweight and cheap — tag liberally. Better to have too many snapshots than too few.
- To list existing tags: `git -C /home/node/.openclaw/repos/openclaw-config tag -l "config-*"`
- To roll back: `git -C /home/node/.openclaw/repos/openclaw-config checkout <tag>` (detached HEAD, read-only). To fully restore, check out main and reset.

Intent: Coherent [I19].
