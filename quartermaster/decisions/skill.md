---
name: decisions
description: Display the decision board for the current project channel. Usage: /decisions
version: 1.0.0
author: relay
tags: [decisions, project, tracking]
---

# decisions

## Invoke

```
/decisions              # Show all decisions for this channel
/decisions open         # Show only UNDECIDED items
/decisions done         # Show only DONE items
```

## Steps

### 1. Find decisions file

Look for `decisions/<channel-name>.md` in workspace.

If not found: reply "No decisions tracked for this channel yet. Use `/decide <status> <text>` to start."

### 2. Format and post

Post the decision table to Discord. Since Discord doesn't render markdown tables well, format as a numbered list:

```
📋 **Decision Board — #<channel-name>**

**DONE:**
1. Use Gemini Flash as daily driver — fast and cheap (2026-03-01)
3. Deploy on Hostinger VPS (2026-03-01)

**WONT-WORK:**
2. Redis caching — overkill for single-user VPS (2026-03-01)

**UNDECIDED:**
4. SQLite vs LanceDB for structured data (2026-03-01)

**SAVE-FOR-LATER:**
5. Voice wake word — need mic hardware first (2026-03-01)

— 5 decisions tracked. Use `/decide` to add, `/project-audit` to verify.
```

### 3. Filter (if specified)

If a filter word is provided, only show decisions matching that status.

## Rules

- Group by status, ordered: DONE → DECIDED-NOT-DONE → UNDECIDED → SAVE-FOR-LATER → WONT-WORK
- Keep original decision numbers (don't renumber when filtering)
- Use Discord-friendly formatting (no markdown tables, use bold + lists)
