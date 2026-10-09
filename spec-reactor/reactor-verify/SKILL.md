---
name: reactor-verify
description: Full 5-store verification for a specific Reactor task
tags: [reactor, verification, handoff, debugging]
version: 1.0.0
---

# Reactor Verify

Verify that a specific Reactor task has complete data across all 5 stores.

## When to use
- "Did task X complete properly?"
- "Is the handoff for task X visible to Relay?"
- "Verify task X end-to-end"

## The 5 Stores

1. **SQL job row** — `jobs` table in reactor-ledger.sqlite
2. **JSONL terminal event** — `reactor.jsonl` with `relay_handoff_required: true`
3. **Outbox result** — `bridge/outbox/<task>-result.json`
4. **Outbox handoff artifact** — `bridge/outbox/<task>-handoff.json`
5. **Bus handoff marker** — `handoff_sent` dedup table in ledger

## How to use

```bash
bash ~/.openclaw/scripts/reactor-ledger.sh full-check <task-id>
```

Returns a verdict: `5/5 ALL_CLEAR` or `N/5 INCOMPLETE` with specifics on which store is missing.

## Response Format

```
Task: <task-id>
Subject: <subject>
Status: <status>
Duration: <duration>
Stores: X/5
  [OK] SQL job row
  [OK] JSONL terminal event
  [OK] Outbox result
  [MISSING] Outbox handoff artifact
  [OK] Bus handoff marker
Action: <what to do if incomplete>
```

## If Incomplete

- Missing handoff artifact: May need manual emit via bridge-reactor.sh logic
- Missing bus marker: relay-handoff-watcher.sh may need restart
- Missing JSONL event: Check reactor.log for the task
- Missing SQL row: Task may not have been processed by bridge-reactor.sh

Intent: Accurate [I01]. Purpose: [P-TBD].
