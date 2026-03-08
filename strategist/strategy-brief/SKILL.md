---
name: strategy-brief
description: Produce an actionable strategy brief on a topic, grounded in transcript evidence and Chartroom data
tags: [strategy, brief, leverage, sustain, educate, analysis, actionable]
version: 1.0.0
---

# /strategy-brief — Actionable Strategy Brief

Produce a focused strategy brief on a topic. Every claim backed by transcript quotes or Chartroom data.

## When to use
- "What's our strategy for X?"
- "How should we approach [market shift / tool / opportunity]?"
- "Brief me on [topic] with recommendations"
- "What does Nate say about [topic] and what should we do?"

## Process
1. Search Chartroom for prior strategy work on the topic
2. Query transcript DB via Research agent's transcript-query skill
3. Cross-reference findings with Chartroom architecture/decision entries
4. Tag every recommendation: LEVERAGE, SUSTAIN, or EDUCATE
5. Name the executing agent for each action item
6. Score opportunities using impact × effort × urgency (1-5 each)

## Output Format
```
## Strategy Brief: [Topic]
**Context**: [Why this matters now — 1-2 sentences]
**Sources**: [Transcript titles + dates, chart IDs]
**Findings**:
1. [Finding] — [source reference]
**Recommendations**:
| # | Action | Tag | Score (I×E×U) | Owner Agent |
**Risk**: [What happens if we ignore this]
```

## Rules
- No recommendation without a source reference
- If transcript coverage is thin, say so — don't pad
- Time-sensitive items flagged prominently
- Under 500 chars summary unless full detail requested

Intent: Resourceful [I07]. Purpose: Strategic intelligence.
