---
name: debug
description: Systematic debugging with hypothesis testing and binary search isolation. Usage: /debug <issue-description>
version: 1.0.0
author: dev
tags: [debug, troubleshoot, fix]
---

# debug

## Invoke

```
/debug <issue description>
/debug <error message>
```

## Steps

### 1. Reproduce
Confirm the issue exists. Run the failing command or check the error state.
If you cannot reproduce, report that and ask for more context.

### 2. Gather evidence
- Read error messages and stack traces carefully
- Check logs: `docker compose logs --tail=50 openclaw-gateway`
- Check config: relevant sections of openclaw.json
- Check file state: permissions, existence, content

### 3. Form hypothesis
State your theory as: "I believe X is happening because Y, which would mean Z."

### 4. Test hypothesis
Run the smallest possible test that would prove or disprove your theory.
- If confirmed: proceed to fix
- If disproven: form next hypothesis, repeat

### 5. Fix
Apply the minimal fix. Do not refactor surrounding code.

### 6. Verify fix
Reproduce the original steps. Confirm the issue is resolved.
Check for regressions in related functionality.

### 7. Report

```
RESULT: Fixed <issue summary>
STATUS: success
ROOT CAUSE: <what was actually wrong>
FIX: <what was changed>
FILES: <files modified>
VERIFY: <how to confirm the fix holds>
```

## Debugging Toolkit
- Logs: `docker compose logs --tail=100 openclaw-gateway 2>&1 | grep -v "level=warning"`
- Config: `docker compose exec openclaw-gateway cat /home/node/.openclaw/openclaw.json`
- Process: `docker compose exec openclaw-gateway ps aux`
- Network: `curl -s http://localhost:18789/`
- Files: `docker compose exec openclaw-gateway ls -la <path>`

## Rules
- Always reproduce before fixing
- Fix root causes, not symptoms
- One fix per issue — do not bundle unrelated changes
- After 3 failed hypotheses, escalate with findings
- Never apply "shotgun debugging" — changing random things hoping something works

Intent: Accurate [I01]. Purpose: [P-TBD].
