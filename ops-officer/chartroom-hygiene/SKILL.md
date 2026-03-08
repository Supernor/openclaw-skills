---
name: chartroom-hygiene
description: Audit and clean stale Chartroom entries — verify, update, or delete.
version: 1.0.0
author: reactor
tags: [ops, chartroom, hygiene, maintenance]
---

# chartroom-hygiene

## Purpose
Maintain Chartroom quality by reviewing stale entries. For each: verify it's still valid knowledge, update with current data, or delete if outdated/redundant/one-off.

## When to run
- On demand: "run chartroom hygiene"
- Weekly cron (recommended after proven)
- After major system changes (agent additions, architecture shifts)

## Process

### 1. Get stale entries
Use `memory_recall` to search for entries, or request a stale scan from the reactor via the bridge.

### 2. For each entry, evaluate

**KEEP and UPDATE if:**
- Still-valid decision, architecture, governance, or procedure
- Agent profile or system fact that reflects current state
- Error/fix pattern that could recur

**DELETE if:**
- One-off session log with no reusable knowledge (nightwork-*, bootcamp-*, test-*)
- Superseded by a newer chart on the same topic
- UUID-based auto-generated entry with no meaningful content
- Reminder or milestone that's been completed
- Reading that's now wrong (outdated model info, old agent count, etc.)

**MERGE if:**
- Two charts cover the same topic — combine into the better-written one, delete the other

### 3. Update format
When updating a chart, ensure:
- Text reflects current system state (13 agents, 94 skills, Codex primary, etc.)
- Ends with `Verified: YYYY-MM-DD`
- Ends with `Intent: [Name] [Code]. Purpose: [P-TBD].`
- Under 500 characters when possible (Chartroom is for compressed wisdom, not essays)

### 4. Work in batches
Process 10-20 entries per invocation. Report progress:
```
Chartroom Hygiene — Batch 1
Reviewed: 15 entries
  Updated: 8
  Deleted: 4
  Skipped (not stale): 3
Remaining stale: ~220
```

### 5. Reporting
After each batch, post a summary to the channel or return to caller.
After all batches complete, post final summary to #ops-nightly.

## Decision authority
- **Act**: Read, evaluate, update charts with current data
- **Act + Notify**: Delete charts that are clearly outdated/one-off
- **Ask First**: Delete charts with importance >= 0.95 or category "decision"/"governance"

## Quality rules
- Be LOSSLESS with decisions and governance — compress but don't lose rationale
- One topic, one chart — if you find duplicates, merge into the better one
- Don't delete something just because you don't recognize it — search for context first
- UUID entries from agents are usually auto-generated preferences or session notes — safe to delete if content is trivial

Intent: Informed [I18], Coherent [I19]. Purpose: [P-TBD].
