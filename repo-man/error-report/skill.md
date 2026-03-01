---
name: error-report
description: Pull recent errors from gateway logs and Repo-Man log, format and send to Discord.
version: 2.0.0
author: repo-man
tags: [logging, errors, reporting]
---

# error-report

## Invoke
```
/error-report          # Last 10 WARN+ entries from all sources
/error-report 25       # Last 25 entries
/error-report today    # All entries from today
```

## Steps

### 1. Query gateway logs (structured, richest source)
```bash
/home/node/.openclaw/scripts/gateway-log-query.sh --errors --summary --limit <N>
```

### 2. Query local Repo-Man log
```bash
grep -E '^\[.+\] (WARN|ERROR|FATAL)' /home/node/.openclaw/workspace-spec-github/logs/repo-man.log | tail -<N>
```

### 3. Check open GitHub incidents
```bash
/home/node/.openclaw/scripts/incident-manager.sh list
```

### 4. Format and send

Combine all sources into a single report:
```
📋 Error Report (last <N> entries)

Gateway Errors:
  [time] LEVEL module — msg
  ...

Repo-Man Errors:
  [time] LEVEL skill — msg
  ...

Open Incidents:
  #<N>: <title>
  (or "None")
```

If no errors found: `[Repo-Man] error-report: All clear. No WARN+ entries found.`

## Notes
- This skill does not modify any logs. Read-only.
- Gateway log has the most data — always query it first
- Use scripts, don't grep docker logs manually
