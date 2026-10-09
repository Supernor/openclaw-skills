# method-review

## Trigger
`/method-review [focus]`

Focus areas: `routing`, `tokens`, `delegation`, `tools`, `parallelism`, `full`

## What It Does
The "Robert Test" — audits recent work for the inefficiency patterns Robert keeps correcting. Scores each category and provides specific recommendations.

## Checks

### 1. Engine Routing Efficiency
- Tools: `helm_report`, `helm_usage`
- Check: Escalation rate, cost distribution, are cheap engines being used where appropriate?
- Bad signal: Everything going to expensive engines, high escalation rate

### 2. Token Efficiency
- Tools: `bootstrap_cost`
- Check: Per-agent bootstrap cost, workspace bloat, oversized files
- Bad signal: Bootstrap over 20K chars, workspace files growing unbounded

### 3. Delegation Patterns
- Tools: `backbone_snapshot`
- Check: Is Reactor doing agent work? Are agents being used or bypassed?
- Bad signal: All work done by one agent, agents idle while manual work happens

### 4. Tool Selection
- Tools: `chart_search`
- Check: Bash where Python is better? Docker exec where MCP exists? Manual where automated could work?
- Bad signal: Repeated shell one-liners for structured data tasks

### 5. Parallelism
- Tools: `backbone_snapshot`
- Check: Sequential work that could be concurrent
- Bad signal: Agent calls made one at a time when they're independent

## Output Format
```
Method Review: [focus] — [date]

| Category | Score | Detail |
|----------|-------|--------|
| Routing | GOOD/NEEDS WORK/POOR | [specifics] |
| Tokens | GOOD/NEEDS WORK/POOR | [specifics] |
| Delegation | GOOD/NEEDS WORK/POOR | [specifics] |
| Tools | GOOD/NEEDS WORK/POOR | [specifics] |
| Parallelism | GOOD/NEEDS WORK/POOR | [specifics] |

Recommendations:
1. [specific action]
2. [specific action]
```

## MCP Tools Used
- `helm_report` — routing analysis
- `helm_usage` — token/cost distribution
- `bootstrap_cost` — workspace bloat check
- `backbone_snapshot` — agent activity patterns
- `chart_search` — tool selection history
- `satisfaction_scores` — fleet health correlation

intent: Efficient [I06], Trusted [I11]
