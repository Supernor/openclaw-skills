---
name: gemini-check
description: Report current Gemini API capabilities, pricing, and operational status
tags: [gemini, status, capabilities, pricing, api]
version: 1.0.0
---

# Gemini Check

Report on Gemini API health, capabilities, and optimal usage patterns.

## When to use
- "Is Gemini working?"
- "What can Gemini do now?"
- "Should we use Flash or Pro for this?"
- "What's our Gemini spend looking like?"

## How to use

### Health check
Test API connectivity with a minimal prompt.

### Capability report
Reference SOUL.md capabilities section + any new findings from ai-news.

### Model selection guidance
- **Flash**: Fast, cheap. Use for search, simple analysis, news gathering.
- **Pro**: Stronger reasoning. Use for complex analysis, multi-step research, ambiguous queries.
- **NEVER**: gemini-3-pro (deprecated March 9, 2026)

### Spend report
Reference MEMORY.md token spend log.

## Output Format
```
## Gemini Status
- API: [healthy/degraded/down]
- Flash: [available/unavailable]
- Pro: [available/unavailable]
- Recent spend: [estimate from log]
- New capabilities: [any from recent ai-news]
- Recommendation: [any config changes suggested]
```

Intent: Observable [I13]. Purpose: [P-TBD].
