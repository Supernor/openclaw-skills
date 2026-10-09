---
name: ask-agent
description: Route requests to OpenClaw agents internally (no Discord dependency)
tags: [routing, agents, internal, captain]
version: 1.0.0
---

# Ask Agent

Route a request to any OpenClaw agent from Claude Code or Reactor, entirely internal.

## When to use
- Need to delegate research, security audits, project management, or other specialist work
- Want Captain to route a task to the right agent automatically
- Need agent results without going through Discord

## Command

```bash
oc agent --agent <agent-id> --message "<request>" --json --timeout <seconds>
```

### Common patterns

**Route via Captain (auto-dispatch):**
```bash
oc agent --agent main --message "Route to Research Agent: <question>" --json --timeout 120
```

**Direct to specialist:**
```bash
oc agent --agent spec-research --message "<question>" --json --timeout 120
oc agent --agent spec-dev --message "<task>" --json --timeout 120
oc agent --agent spec-security --message "<audit request>" --json --timeout 120
```

**Send reply to Discord too:**
```bash
oc agent --agent main --message "<request>" --json --deliver --timeout 120
```

## Agent IDs
Discover dynamically: `oc agents list --json`

## Response format
JSON with `result.payloads[].text` containing the agent's response.

## Rules
- Prefer Captain routing (`--agent main`) unless you know the exact specialist
- Set appropriate `--timeout` (default 600s, use 120 for simple queries)
- This is internal-only — no Discord dependency
- For tasks that need host access, use the Reactor skill instead
