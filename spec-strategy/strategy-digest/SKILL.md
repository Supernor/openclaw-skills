---
name: strategy-digest
description: Weekly strategy rollup — transcript freshness, idea pipeline status, opportunities, action items
tags: [digest, weekly, rollup, status, strategy, report, summary]
version: 1.0.0
---

# /strategy-digest — Weekly Strategy Digest

Produce a complete status rollup of the Strategist's domain.

## When to use
- "What's the strategy status?"
- "Weekly digest"
- "How are ideas looking?"
- Automated weekly cron

## Execution
```bash
strategist digest
```

## Output Includes
- Transcript freshness (latest video date, stale flag)
- Backfill status (summaries, descriptions needing processing)
- Idea pipeline counts by status
- Top 3 proposed ideas
- Approved ideas awaiting build
- Any time-sensitive opportunities

Intent: Informed [I18]. Purpose: Strategic situational awareness.
