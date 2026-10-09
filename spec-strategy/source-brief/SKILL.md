---
name: source-brief
description: Generate a condensed intelligence brief from transcript library with optional theme filtering
tags: [brief, source, intelligence, transcript, themes, summary, research]
version: 1.0.0
---

# /source-brief — Generate Source Brief

Build a condensed brief from the transcript library for strategy analysis.

## When to use
- Before any strategy scan or opportunity analysis
- "Brief me on [theme] from transcripts"
- "What do we know about [topic]?"
- Preparing context for a strategy-brief

## Execution
```bash
strategist source-brief                          # Full brief, all videos
strategist source-brief --themes ai-coding,harness  # Filtered by themes
strategist source-brief --output /tmp/brief.md   # Custom output path
```

## Available Themes
ai-market, ai-coding, model-evaluation, cost-optimization, career-impact,
prompt-engineering, agent-architecture, security, openclaw, leadership,
compute-economics, harness, strategy

## Output
Markdown file at `workspace/memory/source-brief.md` with:
- Video title, date, summary
- Key insights (actionable bullets)
- Description links, people mentioned, key claims

Intent: Informed [I18]. Purpose: Intelligence preparation.
