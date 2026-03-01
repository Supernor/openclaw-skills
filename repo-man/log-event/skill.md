---
name: log-event
description: Internal logging utility for Repo-Man. Called by all other skills. Writes structured log entries locally and pushes WARN+ to GitHub. Never call this directly — it is invoked by other skills.
version: 1.0.0
author: repo-man
tags: [internal, logging]
---

# log-event

## Purpose

Core logging primitive. Every skill calls this. Ensures every operation leaves a complete, structured, retrievable record — locally and on GitHub for WARN+.

## Log Entry Format

```
[ISO8601] LEVEL skill-name
Command: <exact command>
Exit code: <n>
Stderr: <raw stderr, full — never truncate>
Stdout summary: <first 500 chars>
Context: env_vars_present=<comma-separated key names, never values> | cwd=<path> | agent=spec-github
Next action: <what happens as a result>
---
```

## Parameters

| Param | Required | Description |
|-------|----------|-------------|
| level | yes | INFO / WARN / ERROR / FATAL |
| skill | yes | Name of the calling skill |
| command | yes | Exact command that was run |
| exit_code | yes | Integer exit code |
| stderr | yes | Raw stderr (empty string if none) |
| stdout | no | First 500 chars of stdout |
| context | yes | Dict of relevant context (key names only, no values) |
| next_action | yes | What Repo-Man will do as a result |

## Behavior by Level

### INFO
- Append to local log only: `/home/node/.openclaw/workspace-spec-github/logs/repo-man.log`
- No GitHub push

### WARN
- Append to local log
- Append to `openclaw-config/logs/ERRORS.md` (latest at top)
- Commit and push: `[log] WARN <skill> <date>`

### ERROR
- Append to local log
- Append to `openclaw-config/logs/ERRORS.md`
- Commit and push
- Send Discord message to Robert: `[Repo-Man] ERROR in <skill>: <one-line summary>`

### FATAL
- Append to local log
- Append to `openclaw-config/logs/ERRORS.md`
- Commit and push
- Send Discord message: `[Repo-Man] ⚠️ FATAL in <skill>: <one-line summary>. Manual intervention required.`
- Alert pa-admin if agent-to-agent comms are available

## ERRORS.md Entry Format

```markdown
## [ISO8601] LEVEL — skill-name

**Command:** `<command>`  
**Exit code:** `<n>`  
**Stderr:**
\`\`\`
<raw stderr>
\`\`\`
**Context:** `<key names present, cwd, agent>`  
**Next action:** <what happened>

---
```

## LAST_RUN.md Update

After every skill run (regardless of level), update the relevant row in LAST_RUN.md:
```markdown
| <skill> | <ISO8601> | <PASS/FAIL> |
```

Commit: `[last-run] update <skill> <date>`
