---
name: agent-audit
description: Audit agent health — SOUL.md structure, skills, workspace freshness, satisfaction scores. Reports findings and files issues.
version: 1.0.0
author: captain
tags: [fleet, audit, health, satisfaction]
intent: Observable [I13]
---

# agent-audit

Audit one or all agents for health and completeness.

## Trigger
`/agent-audit [agent-id]` or `/agent-audit all`

## What to check per agent

1. **SOUL.md structure** — Must have `## Identity`, `## Purpose`, `## Intents` headers. Missing headers = role clarity gap.
2. **Skills directory** — Must exist and be populated. Each subdirectory must contain a `SKILL.md`.
3. **TOOLS.md** — Must list real skills that match the skills directory. Phantom skills (listed but no SKILL.md) are a flag.
4. **Workspace freshness** — Call `workspace_freshness` MCP tool. Flag files older than 30 days.
5. **Satisfaction score** — Call `satisfaction_scores` MCP tool. Flag agents below fleet average.
6. **IDENTITY.md** — Must exist and be non-empty.
7. **BOOTSTRAP.md** — Should NOT exist. If present, onboarding is incomplete.

## Process

1. If `all`, get agent list from `agents_list` MCP tool. Otherwise audit the named agent.
2. For each agent, run checks 1-7 above.
3. Produce a per-agent report with findings and recommended actions.
4. For each real problem found, file an issue via `issue_log` MCP tool.
5. Search Chartroom via `chart_search` for any existing known issues about the agent.

## Authority
**Report + file issues only.** Do NOT modify agent files directly. Delegate fixes to the appropriate specialist or escalate to Reactor.

## MCP Tools Used
- `satisfaction_scores` — Fleet satisfaction data
- `workspace_freshness` — File ages per agent
- `issue_log` — File issues for problems found
- `chart_search` — Check for existing known issues
- `agents_list` — Get full agent list (for `all` mode)

## Output Format
Per agent:
```
### [agent-id] — Score: XX/100
- SOUL.md: OK / Missing [headers]
- Skills: N skills, M phantom
- Freshness: OK / [N files stale]
- Satisfaction: XX/100 (fleet avg: YY)
- Issues filed: [list]
- Recommended: [actions]
```
