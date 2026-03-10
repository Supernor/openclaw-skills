---
name: agent-satisfaction
description: Run the 19-intent satisfaction scorer across all agents, write report to Chartroom, and trigger self-healing actions on threshold breaches
version: 1.0.0
author: captain
tags: [satisfaction, scoring, intents, health, self-healing]
intent: Observable [I13], Reliable [I05]
---

# Agent Satisfaction

Score all 16 agents across 19 intents. Write results to Chartroom as `report-agent-satisfaction`. Trigger self-healing actions on threshold breaches.

## When to use
- Daily check: report is older than 7 days or missing
- After major changes: new agent created, skills added, config changed
- On demand: when Reactor or Robert asks for fleet health

## Command

Use MCP tools (works from inside container — no host paths needed):

- **Full JSON report**: Use `satisfaction_scores` MCP tool (no args for all agents)
- **Single agent**: Use `satisfaction_scores` MCP tool with `agent: "<agent-id>"`
- **One-liner for sitrep**: Use `satisfaction_summary` MCP tool

Fallback (host only):
```bash
python3 /root/.openclaw/scripts/agent-satisfaction-score.py --json
```

## Procedure

1. Run the scorer: use `satisfaction_scores` MCP tool
2. Parse the JSON output for fleet average and per-agent scores
3. Write summary to Chartroom: `chart update report-agent-satisfaction "<summary>"`
4. Check thresholds and trigger self-healing:

### Self-Healing Thresholds

| Condition | Action |
|-----------|--------|
| Any agent context > 85% | Reset session via `openclaw sessions --agent <id> --reset` |
| Any agent context > 70% recurring (3+ snapshots) | Flag for workload evaluation |
| I03 Competent < 5 | Agent needs skills — flag for Dev |
| I02 Understood < 5 | SOUL.md needs rewrite — flag for Reactor |
| I08 Resilient < 5 | Missing fallback model — fix auth-profiles |
| I05 Reliable < 4 | Chronic errors — investigate model/config |
| Fleet avg < 6.0 | System-wide alert to Reactor |

### Report Format (Chartroom)

```
Fleet avg: X.X/10 (16 agents). [date].
Top: [agent]=X.X. Bottom: [agent]=X.X.
Alerts: [threshold breaches].
Actions taken: [self-healing actions].
```

## Trigger
Captain checks `report-agent-satisfaction` date on first turn each day.
If older than 7 days (or missing), run this skill.

## Rules
- No self-scoring (Captain doesn't score itself higher)
- Unknown (?) is honest — never invent scores without data
- Scores are earned from real signals, not defaults
- System-wide metrics are system scores, not agent scores
