# truth-audit

## Trigger
`/truth-audit [category]`

Categories: `agents`, `charts`, `engines`, `intents`, `infra`, `all`

## What It Does
Runs `reality_check` MCP tool, compares claims vs actual system state, scores accuracy, and logs failures.

## Steps

1. **Search charts first**: `chart_search` for prior truth-audit findings and known issues
2. **Run reality check**: `reality_check` with specified category (or all)
3. **Score results**: Calculate X/Y passed, Z% accuracy
4. **Classify failures**:
   - `DRIFT` — minor: outdated but not wrong (e.g., stale count)
   - `CONTRADICTION` — major: claim conflicts with reality
   - `FALSE` — critical: claim is demonstrably wrong
5. **Log issues**: `issue_log` for each failure with severity
6. **Report to Captain**: Summary with per-failure detail

## Output Format
```
Truth Audit: [category] — [X/Y passed, Z%]

PASS: [claim] ✓
DRIFT: [claim] — expected [X], found [Y]
CONTRADICTION: [claim] — [evidence]
FALSE: [claim] — [evidence]

Issues logged: [N]
Prior findings: [chart IDs if relevant]
```

## MCP Tools Used
- `reality_check` — primary verification
- `chart_search` — prior findings lookup
- `issue_log` — record failures
- `system_status` — supplementary state data

intent: Trusted [I11], Coherent [I09]
