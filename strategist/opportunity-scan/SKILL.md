---
name: opportunity-scan
description: Scan transcript library and Chartroom for revenue, sustainability, and competitive opportunities
tags: [opportunity, revenue, sustainability, competitive, scan, monetization]
version: 1.0.0
---

# /opportunity-scan — Opportunity Scanner

Systematic scan of transcript library and Chartroom for actionable opportunities.

## When to use
- "What opportunities are we missing?"
- "How can we monetize OpenClaw?"
- "What revenue ideas has Nate covered?"
- "Scan for sustainability angles"
- Periodic sweep (weekly recommended)

## Process
1. Search Chartroom for existing opportunity/vision entries
2. Query transcripts for monetization, revenue, cost, business, API, SaaS keywords
3. Cross-reference with our current architecture and capabilities
4. Score each opportunity: impact × effort × urgency (1-5 each, max 125)
5. Filter: only surface opportunities scoring 27+ (3×3×3 minimum)
6. Assign owner agent for each actionable item

## Output Format
```
## Opportunity Scan — [Date]
**Scope**: [What was scanned — transcript count, chart count]

| # | Opportunity | Tag | I×E×U | Score | Source | Owner |
|---|------------|-----|-------|-------|--------|-------|

**Top 3 Actions** (highest score, immediately actionable):
1. [Action] — [Owner agent] — [Why now]

**Parked** (high value but blocked/deferred):
- [Item] — [Blocker]
```

## Rules
- Re-scan should diff against previous scan (check Chartroom for prior opportunity-scan results)
- Don't resurface already-actioned opportunities unless status changed
- Flag if transcript library is stale (>7 days since last ingest)

Intent: Resourceful [I07]. Purpose: Sustainability pipeline.
