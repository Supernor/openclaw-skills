---
name: reactor-ledger-audit
description: Audit the Reactor ledger for data integrity, consistency, and historical analysis
tags: [reactor, ledger, audit, integrity, analytics, retros]
version: 1.0.0
---

# Reactor Ledger Audit

Audit the SQLite ledger for data integrity and produce analytical summaries.

## When to use
- "Audit the reactor ledger"
- "Are there data inconsistencies?"
- "Show me reactor analytics"
- "How has the reactor performed this week?"
- "What are the common failure patterns?"
- "Run a health check on the ledger"

## Required Inputs
- None (full audit)
- Optional: time range, specific task IDs, or focus area (integrity/performance/patterns)

## Audit Checks

### 1. Data Integrity
```bash
# Jobs with missing required fields
sqlite3 ~/.openclaw/bridge/reactor-ledger.sqlite \
  "SELECT task_id, subject FROM jobs WHERE status IS NULL OR date_received IS NULL;"

# Finished jobs missing duration
sqlite3 ~/.openclaw/bridge/reactor-ledger.sqlite \
  "SELECT task_id, subject, status FROM jobs WHERE status IN ('completed','failed') AND duration_seconds IS NULL;"

# Events referencing non-existent jobs
sqlite3 ~/.openclaw/bridge/reactor-ledger.sqlite \
  "SELECT e.task_id, e.event_type FROM events e LEFT JOIN jobs j ON e.task_id = j.task_id WHERE j.task_id IS NULL;"
```

### 2. Lockstep Verification (3-store)
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh lockstep
```

### 3. Performance Summary
```bash
# Average duration by status
sqlite3 -header -column ~/.openclaw/bridge/reactor-ledger.sqlite \
  "SELECT status, COUNT(*) as count, ROUND(AVG(duration_seconds),1) as avg_dur, MAX(duration_seconds) as max_dur, SUM(tool_count) as tools FROM jobs GROUP BY status;"

# Slowest tasks
sqlite3 -header -column ~/.openclaw/bridge/reactor-ledger.sqlite \
  "SELECT task_id, subject, duration_seconds, tool_count FROM jobs WHERE status='completed' ORDER BY duration_seconds DESC LIMIT 5;"
```

### 4. Failure Patterns
```bash
# Failed tasks with result previews
sqlite3 ~/.openclaw/bridge/reactor-ledger.sqlite \
  "SELECT task_id, subject, result_preview FROM jobs WHERE status='failed' ORDER BY date_finished DESC LIMIT 10;"

# Timeout vs error failures
sqlite3 ~/.openclaw/bridge/reactor-ledger.sqlite \
  "SELECT CASE WHEN exit_code = 124 OR result_preview LIKE '%timeout%' THEN 'timeout' ELSE 'error' END as type, COUNT(*) as count FROM jobs WHERE status='failed' GROUP BY type;"
```

### 5. Retro Analysis
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh retros 10
```

### 6. Question/Feedback Review
```bash
# Unanswered questions
bash ~/.openclaw/scripts/reactor-ledger.sh open-questions

# All feedback
sqlite3 -header -column ~/.openclaw/bridge/reactor-ledger.sqlite \
  "SELECT task_id, feedback_to_openclaw, created_at FROM feedback ORDER BY created_at DESC;"
```

## Expected Output

```
Ledger Audit Report:
- Total jobs: N
- Integrity: CLEAN / N issues found
- Lockstep: ALL_AGREE / N mismatches
- Performance:
  - Completed: N (avg: Xs, max: Ys)
  - Failed: N (N timeouts, N errors)
  - Tool usage: N total across all tasks
- Top failure pattern: <pattern>
- Open questions: N
- Undelivered handoffs: N
- Recommendation: <if any>
```

## Safety Constraints
- **Read-only** — never modify the ledger database
- Report findings factually — do not speculate on causes without evidence
- Flag integrity issues as HIGH priority
- If the ledger DB is missing or corrupt, report immediately to Captain

Intent: Observable [I13]. Purpose: [P-TBD].
