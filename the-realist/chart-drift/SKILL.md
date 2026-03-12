# chart-drift

## Trigger
`/chart-drift [topic]`

Topic: any keyword or category (e.g., `agents`, `engines`, `security`, `all`)

## What It Does
Compares chart claims to current system state and flags contradictions. Finds stale, wrong, or outdated charts.

## Steps

1. **Search charts by topic**: `chart_search` with the specified topic
2. **For each chart found**:
   a. Read full content via `chart_read`
   b. Extract verifiable claims (counts, statuses, names, versions)
   c. Verify each claim against MCP tools (`system_status`, `reality_check`, `workspace_freshness`)
   d. Flag drift with evidence
3. **Classify findings**:
   - `STALE` — chart is old but not dangerous (e.g., outdated count)
   - `WRONG` — chart states something demonstrably false
   - `MISSING` — topic has no chart coverage at all
4. **Report to Captain** with specific chart IDs and what they should say

## Output Format
```
Chart Drift Report: [topic] — [date]

Checked: [N] charts
Findings: [M] drift items

STALE: [chart-id] — says "[old claim]", should say "[new state]"
WRONG: [chart-id] — says "[false claim]", reality: "[evidence]"
MISSING: [topic area] — no chart coverage found

Recommended updates: [list of chart IDs + corrections]
```

## MCP Tools Used
- `chart_search` — find relevant charts
- `chart_read` — read full chart content
- `system_status` — current state verification
- `reality_check` — claim verification
- `workspace_freshness` — agent workspace state

intent: Trusted [I11], Coherent [I09]
