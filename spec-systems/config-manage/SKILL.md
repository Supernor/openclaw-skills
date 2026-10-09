---
name: config-manage
description: Safely read and modify OpenClaw config using native CLI (not raw JSON editing)
tags: [config, safety, management]
version: 1.0.0
---

# Config Manage

Read and modify OpenClaw configuration using the native CLI instead of raw jq edits.

## When to use
- Need to read config values
- Need to change a setting safely
- Validate config before restart

## Commands

### Read
```bash
oc config get agents.list                    # Get agent list
oc config get memory.backend                 # Get memory backend
oc config get channels.discord               # Get Discord config
oc config get gateway                        # Get gateway config
oc config get <any.dot.path>                 # Any config value
```

### Write
```bash
oc config set <path> <value>                 # Set a value
oc config unset <path>                       # Remove a value
```

### Validate
```bash
oc config validate                           # Check config against schema
```

### Models (specialized)
```bash
oc models aliases list                       # Current aliases
oc models aliases add <alias> <model>        # Add alias
oc models aliases remove <alias>             # Remove alias
oc models fallbacks list --agent <id>        # Fallback chain
oc models fallbacks add <model> --agent <id> # Add fallback
```

### Agents (specialized)
```bash
oc agents list --json                        # All agents
oc agents add --help                         # Add agent
oc agents bind --help                        # Routing bindings
```

## Safety rules
- Always `oc config validate` after changes
- Back up config before destructive changes: `cp /root/.openclaw/openclaw.json /root/.openclaw/openclaw.json.bak.$(date +%s)`
- Use dead man's switch for risky changes (see schedule-task skill)
- Config changes require: `docker compose restart openclaw-gateway`

Intent: Coherent [I19]. Purpose: [P-TBD].
