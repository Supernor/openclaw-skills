---
name: decide
description: Log a project decision with status and rationale. Usage: /decide <status> <text>
version: 1.0.0
author: relay
tags: [decisions, project, tracking]
---

# decide

## Invoke

```
/decide done Use Gemini Flash as daily driver — fast and cheap
/decide wont-work Redis caching — overkill for single-user VPS
/decide save-for-later Voice wake word — need mic hardware first
/decide undecided Whether to use SQLite or LanceDB for structured data
/decide decided-not-done Custom Discord bot — OpenClaw handles this natively
```

## Statuses

| Status | Meaning |
|--------|---------|
| `done` | Shipped, finalized, implemented |
| `decided-not-done` | Explicitly chose not to do this |
| `undecided` | Still open, needs more discussion |
| `save-for-later` | Good idea, not now |
| `wont-work` | Tried or analyzed, doesn't work — include why |

## Steps

### 0. Enforce project channel scope

**Decisions can only be logged in project channels** (channels with a `decisions/<channel-name>.md` or `projects/<channel-name>.md` file, or channels inside the Projects category).

If `/decide` is used in a general/non-project channel, do NOT log the decision. Instead reply:
```
⚠️ Decisions are scoped to project channels. Either:
- Head to the relevant project channel and `/decide` there
- Use `/project <name>` to create a new project first
```

### 1. Identify the project channel

Use the current Discord channel name as the project scope. If no decisions file exists yet, create one.

### 2. Append to decisions file

File: `decisions/<channel-name>.md` in workspace.

If file doesn't exist, create it with header:
```markdown
# Decisions — <channel-name>

| # | Decision | Status | Why | Date |
|---|----------|--------|-----|------|
```

Append a new row with auto-incrementing number:
```markdown
| <next#> | <text> | <STATUS> | <rationale extracted from text> | <YYYY-MM-DD> |
```

### 3. Confirm

Reply in Discord:
```
✅ Decision #<N> logged: <STATUS> — <short summary>
```

If status is `wont-work`, remind the user this is now on the "don't revisit" list unless explicitly reopened.

## Rules

- Parse the status from the first word after `/decide`
- Everything after the status is the decision text
- If the text includes a dash or "because", split into decision + rationale
- If no rationale given, set Why to "—"
- Never overwrite existing decisions — append only
- Status values are case-insensitive on input, stored uppercase
