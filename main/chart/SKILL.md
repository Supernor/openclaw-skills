---
name: chart
description: Chartroom management via /chart command — search, read, add, update, list, stale
tags: [chartroom, memory, lancedb, knowledge, chart]
version: 1.0.0
---

# /chart — Chartroom Command

User-invocable Discord command for managing the Chartroom (LanceDB knowledge base).

## When to use
- User types `/chart` or `/chart <subcommand>` in Discord
- Any agent needs to perform chartroom operations

## Command Grammar

```
/chart                              — Show help
/chart search <keywords>            — Semantic search
/chart read <id>                    — Read a specific chart
/chart add <id> "<text>" [cat] [imp] — Add new chart
/chart update <id> "<text>" [cat] [imp] — Update existing chart
/chart list [limit]                 — List charts (default 20)
/chart stale                        — Scan for stale entries
```

## Execution

Run the handler script directly:

```bash
bash ~/.openclaw/scripts/chart-handler.sh <subcommand> [args...]
```

### Examples

```bash
bash ~/.openclaw/scripts/chart-handler.sh search "qmd hybrid"
bash ~/.openclaw/scripts/chart-handler.sh read definition-chart
bash ~/.openclaw/scripts/chart-handler.sh add decision-foo "We chose X because Y" course 0.9
bash ~/.openclaw/scripts/chart-handler.sh update decision-foo "Updated text" course 0.9
bash ~/.openclaw/scripts/chart-handler.sh list 10
bash ~/.openclaw/scripts/chart-handler.sh stale
bash ~/.openclaw/scripts/chart-handler.sh help
```

## Safety

- `delete` is blocked by default — requires host CLI with explicit confirmation
- `add` and `update` are non-destructive (update = delete + re-add)
- `stale` is read-only scanning

## Categories

reading, procedure, course, issue, error, agent, vision, model, architecture

## Importance Scale

1.0 = critical (safety, security), 0.9 = important, 0.8 = standard, 0.5 = nice-to-know

Intent: Informed [I18]. Purpose: [P-TBD].
