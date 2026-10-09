---
name: research-troubleshoot
description: Diagnose why a task or agent failed. Check local data first (zero tokens), web search only if needed.
tags: [research, troubleshoot, diagnosis, zero-cost]
version: 1.0.0
---

# research-troubleshoot

Diagnose task or agent failures. LOCAL FIRST — models are the LAST resort.

## When to use
- Task failed and nobody knows why
- Agent has high failure rate
- Pattern of similar failures across multiple tasks
- Babysitter flags an agent for repeated violations

## Process (ordered by cost — cheapest first)

### Step 1: Local data (zero tokens)
```
ops_query: SELECT id, agent, status, substr(task,1,80), substr(errors,1,200), substr(outcome,1,200), duration_ms FROM tasks WHERE agent='<agent>' AND status IN ('blocked','failed','cancelled') ORDER BY id DESC LIMIT 10
```
Look for:
- Repeated error patterns (same error across tasks = systemic)
- Timing patterns (all fail at same time = infrastructure)
- Engine patterns (all gemini-run fail = engine broken, not task broken)

### Step 2: Chart search (zero tokens)
```
chart search "<error keyword>"
chart search "<agent name> failure"
chart search "issue-<pattern>"
```
Someone may have already diagnosed and charted this.

### Step 3: Log scan (zero tokens)
```
ops_query: SELECT key, substr(value,1,200) FROM kv WHERE key LIKE 'truth_violation_%' AND value LIKE '%<agent>%' ORDER BY key DESC LIMIT 5
```
Check executor log, stability log, babysitter log for the timeframe.

### Step 4: Engine health check (zero tokens)
```
ops_query: SELECT engine, COUNT(*), SUM(success), ROUND(AVG(duration_ms)) FROM engine_usage WHERE engine='<engine>' GROUP BY engine
```
If engine success rate is low, the problem is the engine, not the task.

### Step 5: Web search (free — only if Steps 1-4 insufficient)
Use `web-search` skill with specific error message or pattern.
Example: "OpenClaw codex-run exit code 124 timeout" or "NVIDIA NIM API headers timeout error"

### Step 6: Model synthesis (costs tokens — only for complex diagnosis)
Only after Steps 1-5 have gathered data. Summarize findings, propose fix.

## Output Format
```
## Diagnosis: [Agent/Task #ID]
**Pattern**: [What's failing and how often]
**Root cause**: [Infrastructure/Engine/Prompt/Logic]
**Evidence**: [Which step found it, what data]
**Fix**: [Specific action — file, line, change]
**Prevention**: [Chart to add, policy to enforce]
**Cost of diagnosis**: [Zero / Free web search / N tokens]
```

## Chart findings immediately
Every diagnosis = a chart. Even "I couldn't find the cause" is worth charting to save the next investigator time.
