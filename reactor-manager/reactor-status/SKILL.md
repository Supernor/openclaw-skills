---
name: reactor-status
description: Query the Reactor ledger and report current operational status
tags: [reactor, status, monitoring, ledger]
version: 1.0.0
---

# Reactor Status

Query the Reactor's SQLite ledger and report operational state.

## When to use
- "What's the reactor doing?"
- "How many tasks ran today?"
- "Are there stuck tasks?"
- "Show me reactor stats"

## Source-of-Truth Priority

1. **Primary**: `bridge.sh status` — live file-based inbox/outbox counts (ground truth for pending/inProgress)
2. **Secondary**: `reactor-status.sh` — unified JSON combining service state + bridge stats
3. **Tertiary**: `reactor-ledger.sh` — historical data, analytics, lockstep checks

Always prefer bridge.sh for current queue state. Use ledger for history and diagnostics.

## How to use

### Bridge Overview (PRIMARY — use first)
```bash
bash ~/.openclaw/scripts/bridge.sh status
```
Returns live pending/inProgress/completed counts from actual inbox/outbox files.

### Unified Health Check (JSON)
```bash
bash ~/.openclaw/scripts/reactor-status.sh --pretty
```
Returns a single JSON object: reactor online/offline, service state, claude version, bridge queue counts, uptime, sourceOfTruth, and notes. Works from container (graceful fallbacks for host-only fields).

### Quick Ledger Status
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh status
```
Returns job counts by status, average duration, total tools used.

### Recent Jobs
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh recent 10
```

### Open Questions
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh open-questions
```

### Recent Retros
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh retros 5
```

### Lockstep Health (fleet-wide)
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh lockstep
```
Shows whether SQL, JSONL, and handoff stores agree for every job.

## Output Format

Return a structured summary:
```
Reactor Status:
- Jobs: X completed, Y failed, Z pending
- Avg duration: Ns
- Stuck: none / [list task IDs]
- Open questions: N
- Lockstep: OK / [mismatches]
```
