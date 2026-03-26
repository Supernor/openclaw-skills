---
name: workshop-monitor
description: Track Workshop ideas through stages. Flag stalled ideas, report pipeline health, suggest next actions.
tags: [workshop, monitor, pipeline, kanban]
version: 1.0.0
---

# workshop-monitor — Pipeline Health

## When to use
- Nightly school session (automatic)
- When Robert asks "what's in the workshop?"
- When routing new work (check for overlap with existing ideas)

## Procedure

1. Read ideas-registry.json for all ideas and their stages
2. For each idea, check:
   - How long has it been in the current stage?
   - Are there tasks in ops.db for this idea? What's their status?
   - Is the idea stalled (no activity for 48+ hours)?
3. Report: pipeline summary (count per stage), stalled ideas, recommended actions
4. For stalled ideas: create a bearings question for Robert — "This idea has been in Shape for 3 days. Should we: advance it, archive it, or assign someone to work on it?"

## Stage health thresholds
- Shape: stale after 7 days (ideas should be shaped within a week)
- Gauntlet: stale after 3 days (debate should complete quickly)
- Green Light: stale after 1 day (should split into tasks immediately)
- Build: stale after 14 days (depends on task complexity)
- Proof: stale after 7 days (verification shouldn't linger)

## Tools
- Read ideas-registry.json via exec
- ops_query for task status per idea
- bearings_ask for stalled idea decisions
- chart_search for existing workshop charts
