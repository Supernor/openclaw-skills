---
name: reactor-handoff-ops
description: Verify and troubleshoot Reactor-to-Relay handoff artifacts — ensure results reach the requesting agent
tags: [reactor, handoff, relay, outbox, verification]
version: 1.0.0
---

# Reactor Handoff Ops

Verify that Reactor results successfully hand off to the requesting agent via Relay.

## When to use
- "Did task X reach Relay?"
- "Is the handoff stuck?"
- "Check handoff status for recent tasks"
- "Why didn't Relay get the result?"
- "Verify the return path"

## Required Inputs
- **task-id** (for single-task verification)
- None (for fleet-wide handoff health check)

## The Handoff Chain
```
Reactor completes task
  -> writes outbox/<task>-result.json
  -> sets relay_handoff_required=1 in ledger
  -> writes JSONL lifecycle event (done/fail)
  -> posts completion embed to #ops-reactor
  -> relay-handoff-watcher.sh detects terminal event
  -> sets relay_handoff_sent=1 in ledger
  -> requesting agent polls bridge.sh check and picks up result
```

## How to use

### Single task verification (5-store check)
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh full-check <task-id>
```

### Fleet-wide handoff health
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh lockstep
```

### Check for orphaned handoffs
```sql
-- Tasks where handoff was required but never sent
sqlite3 ~/.openclaw/bridge/reactor-ledger.sqlite \
  "SELECT task_id, subject, status, date_finished FROM jobs WHERE relay_handoff_required=1 AND relay_handoff_sent=0 AND status IN ('completed','failed') ORDER BY date_finished DESC LIMIT 10;"
```

### Check outbox for result files
```bash
ls -lt ~/.openclaw/bridge/outbox/*-result.json 2>/dev/null | head -10
```

### Check JSONL for terminal events
```bash
tail -20 ~/.openclaw/bridge/events/reactor.jsonl | grep -E '"(done|fail|force-fail)"'
```

## Expected Output

```
Handoff Status for <task-id>:
- Outbox result: [EXISTS/MISSING]
- Ledger handoff_required: [1/0]
- Ledger handoff_sent: [1/0]
- JSONL terminal event: [EXISTS/MISSING]
- Ops-reactor embed: [POSTED/UNKNOWN]
- Verdict: ALL_CLEAR / INCOMPLETE — <details>
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| handoff_required=1, handoff_sent=0 | Watcher missed event | Restart relay-handoff-watcher.sh |
| Missing outbox result | bridge-reactor.sh crashed mid-task | Check for force-fail event in JSONL |
| Missing JSONL event | bridge-reactor.sh version pre-hardening | Update bridge-reactor.sh |
| Result exists but agent didn't get it | Agent didn't poll bridge.sh check | Re-send check or notify agent |

## Safety Constraints
- **Read-only** — never modify outbox files, ledger, or JSONL
- Flag orphaned handoffs (age > 5 min) as urgent
- Escalate to Captain if handoff chain is broken for multiple tasks
