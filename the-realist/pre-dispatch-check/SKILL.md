# pre-dispatch-check

## Trigger
`/pre-dispatch [topic]`

## What It Does
Before work is dispatched to an agent or engine, verifies that chart context was searched. Produces a context package so downstream work doesn't rediscover known information.

## Steps

1. **Search charts**: `chart_search` for the topic
2. **Read relevant charts**: `chart_read` for top matches
3. **Summarize findings**: Extract key facts, prior decisions, known issues
4. **Package context**: Format for attachment to dispatch

## Output Format
```
Pre-Dispatch Context: [topic]

Prior charts found: [N]

Key findings:
- [chart-id]: [relevant fact]
- [chart-id]: [relevant fact]

Known issues:
- [issue-id]: [status, impact]

Recommended approach based on prior work:
[summary]

---
Attach this context to the dispatch.
```

If no prior context exists:
```
Pre-Dispatch Context: [topic]
No prior chart context found. This appears to be new territory.
Proceed with standard approach — chart findings when complete.
```

## MCP Tools Used
- `chart_search` — find relevant prior work
- `chart_read` — read full chart details
