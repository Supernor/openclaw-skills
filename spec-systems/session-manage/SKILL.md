---
name: session-manage
description: Manage agent sessions — list, cleanup stale, inspect active conversations
tags: [sessions, cleanup, maintenance]
version: 1.0.0
---

# Session Manage

Monitor and maintain agent conversation sessions.

## When to use
- Sessions growing large or stale
- Need to see what agents are actively working on
- Periodic maintenance

## Commands

### List sessions
```bash
oc sessions --all-agents --json         # All agents
oc sessions --agent relay --json        # Specific agent
oc sessions --active 60 --json          # Active in last 60 min
```

### Cleanup stale sessions
```bash
oc sessions cleanup --all-agents --dry-run    # Preview what would be cleaned
oc sessions cleanup --all-agents              # Execute cleanup
oc sessions cleanup --agent relay             # Single agent
```

## Rules
- Always `--dry-run` first
- Check with Robert before cleaning sessions on active project channels

Intent: Efficient [I06]. Purpose: [P-TBD].
