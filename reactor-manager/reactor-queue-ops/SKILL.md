---
name: reactor-queue-ops
description: Monitor and manage the Reactor task queue — check pending tasks, queue depth, and ordering
tags: [reactor, queue, inbox, pending, monitoring]
version: 1.0.0
---

# Reactor Queue Ops

Monitor the Reactor inbox and pending task queue.

## When to use
- "What's in the reactor queue?"
- "How many tasks are waiting?"
- "Is there a backlog?"
- "Show pending reactor tasks"
- "What's next in line?"

## Required Inputs
- None (queries current state)
- Optional: filter by priority or requesting agent

## How to use

### Check inbox (pending tasks not yet picked up)
```bash
bash ~/.openclaw/scripts/bridge.sh check reactor
```

### Check pending jobs in ledger
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh status
```
Look at the `pending` row for queue depth.

### Recent jobs (to see what's running or just finished)
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh recent 5
```

### List inbox files directly
```bash
ls -lt ~/.openclaw/bridge/inbox/*.json 2>/dev/null || echo "Queue empty"
```

## Expected Output

Return structured queue summary:
```
Queue Status:
- Inbox: N tasks pending pickup
- Ledger pending: N
- Ledger in-progress: N (task: <id> if any)
- Next up: <subject> (priority: <priority>)
- Queue order: FIFO by date_received
```

## Safety Constraints
- **Read-only** — never modify inbox files or ledger entries
- **Serialized lane** — only one task runs at a time. If in-progress exists, all others wait.
- Report queue depth honestly. If backlog > 3, flag it as a concern.
