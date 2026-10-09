---
name: data-path-audit
description: Audit task routing quality, engine success rates, and token spend. Weekly duty for Ops Officer.
tags: [ops, routing, quality, audit, zero-cost]
version: 1.0.0
---

# data-path-audit

Audit the quality of every data path in the system. Identify broken routes, waste, and improvement opportunities.

## When to use
- Weekly scheduled audit (Ops Officer duty)
- After any routing change
- When task failure rate spikes
- When Robert asks "why are things stuck?"

## Process (ALL zero-token — pure SQL + bash)

### Step 1: Route success rates
```sql
SELECT json_extract(meta, '$.host_op') as route,
  COUNT(*) as total,
  SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as ok,
  ROUND(100.0 * SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) / COUNT(*)) as pct
FROM tasks WHERE meta IS NOT NULL
AND json_extract(meta, '$.host_op') IS NOT NULL
AND created_at > datetime('now', '-7 days')
GROUP BY route ORDER BY total DESC;
```

### Step 2: Engine health
```sql
SELECT engine, COUNT(*) as calls, SUM(success) as ok,
  ROUND(100.0 * SUM(success) / COUNT(*)) as pct,
  ROUND(AVG(duration_ms)/1000.0, 1) as avg_sec
FROM engine_usage
WHERE timestamp > datetime('now', '-7 days')
GROUP BY engine ORDER BY calls DESC;
```

### Step 3: Failure pattern clustering
```sql
SELECT SUBSTR(errors, 1, 60) as pattern, COUNT(*) as count
FROM tasks WHERE status IN ('blocked','failed')
AND created_at > datetime('now', '-7 days')
AND errors IS NOT NULL AND errors != ''
GROUP BY pattern ORDER BY count DESC LIMIT 10;
```

### Step 4: Token waste detection
Look for:
- Tasks that failed after spending tokens (engine_usage has the call, task is blocked)
- Duplicate tasks (same task text, different IDs)
- Auto-heal chains that consumed tokens then got cancelled
```sql
SELECT agent, COUNT(*) as retries
FROM tasks WHERE task LIKE 'Fix:%' OR task LIKE 'Auto-fix:%'
AND created_at > datetime('now', '-7 days')
GROUP BY agent ORDER BY retries DESC;
```

### Step 5: Routing recommendations
Compare current routes against policy at `/root/.openclaw/docs/routing-policy.md`.
Flag any route below its quality target.

## Output Format
```
## Data Path Audit: [Date]
**Routes**: [table of route / total / success% / target%]
**Engines**: [table of engine / calls / success% / avg latency]
**Top failure patterns**: [clustered errors]
**Token waste**: [retries that burned tokens before cancelling]
**Recommendations**: [specific routing changes]
```

## Escalation
- Route below 50% success: create issue chart + feedback question
- Engine at 0% success: disable the route, alert immediately
- Token waste >10 calls/week on retries: tighten auto-heal guards
