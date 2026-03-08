---
name: transcript-analyze
description: Deep thematic analysis of specific transcripts or cross-cutting topics across the library
tags: [transcript, analyze, theme, pattern, deep-dive, nate-jones]
version: 1.0.0
---

# /transcript-analyze — Deep Transcript Analysis

Thematic deep-dive into one or more transcripts. Finds patterns, contradictions, and evolving positions.

## When to use
- "Analyze [specific video title]"
- "How has Nate's position on [topic] changed over time?"
- "What patterns emerge across the [cost / coding / market] videos?"
- "Compare what Nate said about X in February vs March"
- "Find contradictions in the transcript library"

## Process
1. Check Chartroom for prior analysis on the topic
2. Pull relevant transcripts via Research agent's transcript-query
3. For single video: extract thesis, evidence, predictions, action items
4. For cross-cutting: map theme evolution across dates, find turning points
5. Tag findings: LEVERAGE, SUSTAIN, or EDUCATE
6. Flag predictions that are verifiable — note verification date

## Output Format
```
## Transcript Analysis: [Topic/Title]
**Scope**: [N videos, date range]
**Thesis**: [Core argument in 1-2 sentences]

### Key Points
1. [Point] — [video, date]

### Evolution (if cross-cutting)
| Date | Position | Video |
|------|----------|-------|

### Predictions (verifiable)
| Claim | Verify By | Status |
|-------|-----------|--------|

### Strategic Takeaway
[What this means for us — tagged LEVERAGE/SUSTAIN/EDUCATE]
```

## Rules
- Quote directly when the original wording matters
- Flag contradictions explicitly — they're valuable signal
- Date everything — positions shift fast in AI
- If analysis needs more transcripts ingested, request via Research

Intent: Informed [I18]. Purpose: Deep intelligence extraction.
