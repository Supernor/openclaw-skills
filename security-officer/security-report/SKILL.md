---
name: security-report
description: Produce a periodic security posture summary
tags: [security, report, posture, summary]
version: 1.0.0
---

# Security Report

Produce a summary of the current security posture.

## When to use
- Weekly security check-in
- "What's our security status?"
- "Any security concerns?"
- After infrastructure changes

## Process
1. Review Chartroom for existing `security-*` findings
2. Check if any previous findings have been resolved
3. Run a light audit across all areas (not deep — just surface check)
4. Score overall posture
5. Compare to last report if available

## Output Format
```
## Security Posture — [Date]

### Overall: [GREEN/YELLOW/RED]

### Open Findings
| Severity | Count | Oldest |
|----------|-------|--------|

### Resolved Since Last Report
- [list]

### New Findings
- [list]

### Trust Level: [1/2/3]
### False Positive Rate: [N/total findings]
```

Store as Chartroom reading: `report-security-posture`
