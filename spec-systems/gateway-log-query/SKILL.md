---
name: gateway-log-query
description: Query structured gateway JSON logs. Runs gateway-log-query.sh script.
version: 1.0.0
author: repo-man
tags: [logging, gateway, debugging]
---

# gateway-log-query

## Invoke
```
/gateway-logs                    # Last 20 entries (summary)
/gateway-logs errors             # WARN/ERROR/FATAL only
/gateway-logs models             # Model/auth/fallback related
/gateway-logs --since 10         # Last 10 minutes
/gateway-logs --module discord   # Filter by subsystem
```

## Steps

### 1. Map user request to script args

| User says | Script args |
|-----------|-------------|
| `/gateway-logs` | `--summary --limit 20` |
| `/gateway-logs errors` | `--errors --summary --limit 20` |
| `/gateway-logs models` | `--models --summary --limit 30` |
| `/gateway-logs --since N` | `--since N --summary` |
| `/gateway-logs --module X` | `--module X --summary` |
| `/gateway-logs full` | `--limit 10` (no --summary = full JSON) |

### 2. Run the script
```bash
/home/node/.openclaw/scripts/gateway-log-query.sh [args]
```

### 3. Format output

Present entries in a readable format. The last line is metadata with total log size.

If `--summary` was used, entries have `time`, `level`, `module`, `msg` fields — format as:
```
[time] LEVEL module — msg
```

## Notes
- Gateway log is at /tmp/openclaw/openclaw-YYYY-MM-DD.log (structured JSON, ~6MB/day)
- This is the richest data source — has every API call, error, model fallback
- Use this INSTEAD OF grepping docker compose logs
- Script uses jq for filtering — much faster than LLM parsing

Intent: Observable [I13]. Purpose: [P-TBD].
