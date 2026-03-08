---
name: retrospective
description: Produce a retrospective analysis — weekly or on-demand. Surface patterns in mistakes, wins, decisions, and working style evolution.
version: 1.0.0
author: historian
tags: [retro, retrospective, analysis, patterns]
intent: Coherent [I19]
---

Generate a retrospective analysis.

1. Search session journals for the period (default: last 7 days)
2. Search mistake and win patterns from the period
3. Search decisions made and their outcomes (if known)
4. Produce a structured retrospective:
   - **What worked** — top wins, effective patterns
   - **What didn't** — recurring mistakes, failed approaches
   - **What changed** — decisions, policies, new tools/agents
   - **Working style evolution** — how Robert and the system refined collaboration
   - **Recommendations** — concrete next actions based on patterns
5. Chart as `retro-weekly-YYYY-MM-DD` or `retro-monthly-YYYY-MM` category `reading`
6. Keep under 500 chars for chart, write full analysis to `/home/node/.openclaw/retro-latest.md`
