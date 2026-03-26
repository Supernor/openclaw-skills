---
name: research-upstream
description: Track OpenClaw upstream changes, releases, and leverage opportunities. Weekly audit.
tags: [research, upstream, openclaw, releases]
version: 1.0.0
---

# research-upstream

Track what changed in OpenClaw upstream. Find features we can leverage and breaking changes we need to handle.

## When to use
- Weekly audit (cron-triggered)
- Before any `git pull --rebase` update
- When considering new OpenClaw features
- Repo-Man (spec-github) delegates deep analysis here

## Process

### Step 1: Git diff (zero tokens)
```bash
cd /root/openclaw
git fetch origin 2>/dev/null
# What's new upstream?
BEHIND=$(git rev-list HEAD..origin/main --count 2>/dev/null)
echo "Commits behind: $BEHIND"
# Summary of changes
git log --oneline HEAD..origin/main | head -20
# Which areas changed?
git diff --stat HEAD..origin/main | tail -5
```

### Step 2: Changelog check (zero tokens)
```bash
# Read upstream changelog for user-facing changes
git show origin/main:CHANGELOG.md | head -50
```

### Step 3: Impact assessment (zero tokens)
Check if upstream changes touch files we customized:
```bash
# Our local modifications
git diff --name-only HEAD -- src/ | head -20
# Overlap with upstream changes
git diff --name-only HEAD..origin/main -- src/ | head -20
```

### Step 4: Web search for context (free)
Use `web-search` skill:
- "OpenClaw latest release notes"
- "OpenClaw [specific feature] documentation"

### Step 5: Leverage opportunities (may need model for synthesis)
Only if Steps 1-4 reveal significant changes worth analyzing.

## Output Format
```
## Upstream Report: [Date]
**Commits behind**: [N]
**Key changes**: [Bullet list of significant items]
**Breaking risks**: [Files we modified that also changed upstream]
**Leverage opportunities**: [New features we should adopt]
**Recommended action**: [Pull now / Wait / Cherry-pick specific commits]
```

## Chart findings
- `reading-upstream-YYYY-MM-DD` with key findings
- `issue-upstream-*` for breaking changes that need attention
