---
name: triage
description: What needs attention — open issues, pending bearings, low satisfaction, stale charts. Prioritized.
version: 1.0.0
author: captain
tags: [triage, priority, issues, attention]
intent: Connected [I10]
---

# triage

Surface what needs attention, prioritized by urgency.

## Trigger
`/triage`

## Process

1. Call `issue_list` — open issues, sorted by severity.
2. Call `bearings_pending` — unanswered vision questions from Robert/Corinne.
3. Call `chart_search` for items tagged stale or flagged.
4. Call `satisfaction_scores` — any agent below threshold (< 70/100).
5. Call `provider_health` — if all providers unreachable = P0 critical.
6. Prioritize results:
   - **P0 Critical**: Open issues marked critical, all providers down
   - **P1 High**: Unanswered bearing questions, agents below 50/100
   - **P2 Medium**: Agents 50-70/100, stale charts with action items
   - **P3 Low**: Flagged charts, minor workspace issues

## MCP Tools Used
- `issue_list` — Open issues
- `bearings_pending` — Unanswered vision questions
- `chart_search` — Stale/flagged items
- `satisfaction_scores` — Agent scores
- `provider_health` — API provider reachability (all-down = P0)

## Output Format
```
# Triage — [date]

## P0 Critical
- [issue or "None"]

## P1 High
- [items]

## P2 Medium
- [items]

## P3 Low
- [items]

## Recommended next action
[Single most impactful thing to do right now]
```
