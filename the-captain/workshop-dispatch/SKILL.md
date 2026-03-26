---
name: workshop-dispatch
description: Split a Green Light idea into properly-sized automation tasks with dependencies. One task = one thing.
tags: [workshop, dispatch, task-split, greenlight, build]
version: 1.0.0
---

# workshop-dispatch — Post-Gauntlet Task Splitting

## When to use
After an idea passes the Gauntlet and reaches Green Light. Split it into tasks that automation can handle.

## Procedure

1. Read the idea from ideas-registry.json (or ops_query for DB version)
2. Extract: title, capabilities, success_test, constraints, category
3. For each capability, create ONE task:
   - Agent: route based on type (bridge work → spec-design, code → spec-dev, research → spec-research)
   - Scope: one file, one deliverable, under 5 min engine time
   - Verification: specific check from the success_test
   - Host_op: bridge-edit for UI, codex-run for code, reactor-dispatch for orchestration
4. Set blocked_by dependencies (what must finish before what starts)
5. Create all tasks via ops_insert_task
6. Update idea stage to "build" in registry

## Task sizing rules (from docs/policy-honesty.md)
- Max: one file focus, one deliverable, under 5 minutes
- If a capability needs 2+ files → split into 2 tasks
- If a capability needs research first → research task blocks build task
- Always include verification criteria

## Example
Idea: "Agent Dashboard"
Capabilities: "Monitor agents, Track progress, Get alerts, See who's working"

Tasks:
1. "Dashboard API: GET /api/agents/status" (spec-dev, codex-run)
2. "Dashboard UI: agent cards with status" (spec-design, bridge-edit, blocked_by: 1)
3. "Dashboard alerts: highlight unhealthy agents" (spec-design, bridge-edit, blocked_by: 2)
4. "Dashboard: live update via SSE" (spec-dev, codex-run, blocked_by: 1)

## Tools
- `ops_insert_task` — create each task
- `chart_search` — check if similar work already exists
- `ideas-registry.json` — read idea details
