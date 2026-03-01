---
name: log-decision
description: Append a timestamped decision to DECISIONS.md in openclaw-config and push. Invoke with /decision <text>.
version: 1.0.0
author: repo-man
tags: [decisions, audit, github]
---

# log-decision

## Invoke

```
/decision <text>
```

## Steps

### 1. Format entry
```markdown
## [ISO8601] — <text>

**Logged by:** spec-github (Repo-Man)
**Status:** FINALIZED

---
```

### 2. Prepend to DECISIONS.md (latest at top)
### 3. Commit and push
### 4. Log result and confirm to Robert

## Rules
- Decisions are never deleted or modified after push. Append only.
- If Robert asks to "undo" a decision: log a new entry noting the reversal, never edit the original.
