# intent-coverage

## Trigger
`/intent-coverage`

## What It Does
Runs intent alignment audit across the fleet. Finds blind intents (no measurement), orphan intents (measured but unassigned), and coverage gaps.

## Steps

1. **Run intent audit**: `intent_audit` for full fleet scan
2. **Get satisfaction scores**: `satisfaction_scores` for current measurements
3. **Cross-reference**: Which intents have active measurement? Which are dark?
4. **Build coverage matrix**: Agent x Intent grid showing coverage

## Output Format
```
Intent Coverage Report — [date]

Coverage: [X/Y intents measured, Z%]

| Intent | ID | Measured By | Score | Status |
|--------|----|-------------|-------|--------|
| Trusted | I11 | reality_check | 95.8% | COVERED |
| Responsive | I01 | satisfaction | 8.2 | COVERED |
| ... | ... | ... | ... | ... |
| [Name] | [ID] | — | — | BLIND |

Blind intents (no measurement): [list]
Orphan intents (measured, no owner): [list]
Recommendations: [specific actions to close gaps]
```

## MCP Tools Used
- `intent_audit` — fleet intent alignment scan
- `satisfaction_scores` — current measurement data

intent: Coherent [I09], Trusted [I11]
