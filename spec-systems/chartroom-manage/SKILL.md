---
name: chartroom-manage
description: Full Chartroom (LanceDB) management from Claude Code
tags: [memory, chartroom, lancedb, knowledge]
version: 1.0.0
---

# Chartroom Manage

Manage the Chartroom (LanceDB knowledge base) using both host tools and native CLI.

## When to use
- Store findings, procedures, decisions, error fixes
- Search for prior knowledge before solving a problem
- Audit chartroom health and coverage

## Host tools (fast, from Claude Code)

```bash
chart add <id> <text> [category] [importance]
chart read <id>
chart search <keywords>
chart list [limit]
chart delete <id>
```

Categories: reading (facts), procedure (how-to), course (decisions), issue (problems), error (WHAT/WHY/FIX), agent (agent profiles)

## Container CLI (native, more features)

```bash
oc ltm search <query>           # Semantic search
oc ltm list                     # List all
oc ltm stats                    # Stats by category
oc memory search <query> --json # Workspace file search (different from ltm)
oc memory status                # Index health
oc memory index --force         # Reindex
```

## Conventions
- Error charts: `error-<PREFIX>-<name>` with WHAT BROKE / WHY / FIX
  - Prefixes: PM, SYS, BRIDGE, DISCORD, MODEL, AGENT
- Procedures: `procedure-<name>`, importance 0.9+
- Decisions: `course-<name>`, importance 0.9+
- Agent profiles: `agent-<id>`, importance 0.85

## Rules
- Search before creating — don't duplicate
- Importance: 1.0 = critical (safety, security), 0.9 = important, 0.8 = standard, 0.5 = nice-to-know
- Charts are durable knowledge, not session state

Intent: Informed [I18]. Purpose: [P-TBD].
