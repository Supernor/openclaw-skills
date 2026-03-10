---
name: helm-health
description: Report on Helm routing health — escalation rate, learned patterns, routing efficiency. Use when asked about engine routing performance or during sitrep generation.
version: 1.0.0
author: quartermaster
tags: [helm, routing, metrics, efficiency]
intent: Efficient [I06], Observable [I04]
---

# helm-health

Report on the Helm (engine-router) routing system health.

## When to use
- During sitrep generation (include Helm metrics)
- When Reactor asks about routing efficiency
- Weekly review of engine routing patterns
- After significant changes to engine configs

## Process
1. Read `/root/.openclaw/logs/escalation.log` — count escalations and de-escalation hints
2. Read `/root/.openclaw/engines/helm-learned.json` — count learned patterns
3. Read `/root/.openclaw/logs/helm-metrics.json` — check trend (escalation rate over time)
4. Compute:
   - Current escalation rate (escalations / total tasks routed)
   - Week-over-week trend (improving, flat, degrading)
   - Top unresolved bounce reasons (patterns not yet learned)
   - Cost of escalation waste (sum of wasted tokens from misroutes)
5. Report concisely:
   - Escalation rate: X% (trend: ↓ improving / → flat / ↑ degrading)
   - Learned patterns: N (last learned: date)
   - Top bounces: list of frequent escalation reasons not yet covered
   - Recommendation: "run helm-learn --apply" if new patterns pending

## Output Format
Include in sitrep under "## Helm Routing" section. Keep under 10 lines.
