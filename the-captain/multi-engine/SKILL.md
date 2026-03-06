---
name: multi-engine
description: Route work to the right engine (Reactor, Sub-reactor, Agents) based on task characteristics
tags: [routing, reactor, gemini, agents, efficiency]
version: 1.0.0
---

# Multi-Engine Routing

Three engines available. Route work to the right one based on task needs.

## Engines

| Engine | Tool | Strengths | Cost | Trigger |
|--------|------|-----------|------|---------|
| Reactor | `claude -p` via bridge | Deep reasoning, complex code, architecture | Flat rate (time) | `bridge.sh send` |
| Sub-reactor | `gemini-task` | Web research, batch ops, file scanning | Free (1000 RPD) | `gemini-task "prompt"` |
| Agents | `oc agent` | Domain expertise, memory, tool access | Flat rate (Codex) | `oc agent --agent <id>` |

## Decision matrix

**Use Reactor when:**
- Task needs host access (Docker, VPS, files outside container)
- Complex multi-step coding or debugging
- Source code analysis or modification
- Tasks that need Opus-level reasoning

**Use Sub-reactor (Gemini) when:**
- Web research (has Google Search built in)
- Bulk file scanning or auditing
- Tasks that are broad but shallow
- Reactor is in backoff/limp mode
- Need to preserve Reactor time for heavier work

**Use Agents when:**
- Task fits an existing agent's specialty
- Need domain knowledge (security, research, PM, GitHub)
- Task can be done inside the container
- Want Chartroom access and memory

## Parallel execution
All three engines can run simultaneously:
```bash
# Agent researches while Reactor codes while Gemini scans
oc agent --agent spec-research --message "Research X" --json &
gemini-task "Scan all SKILL.md files for missing versions" --dir /root/.openclaw &
# Reactor handles the heavy lifting in the main flow
```

## MCP as shared protocol
Claude Code, Gemini CLI, and OpenClaw all support MCP servers. An MCP server built once works across all three engines.

### OpenClaw native MCP (mcp-bridge plugin)
Agents can use external MCP servers directly — configured per-agent in `openclaw.json`:
```json
{
  "agents": {
    "list": [{
      "id": "spec-dev",
      "mcp": {
        "servers": [{
          "name": "chartroom",
          "command": "node",
          "args": ["/path/to/chartroom-mcp.js"],
          "type": "stdio"
        }]
      }
    }]
  }
}
```
- Supports: `stdio`, `sse`, `http` transports
- Auto-namespaces tools: `serverName_toolName` (prevents collisions)
- Per-agent provisioning = strict capability boundaries
- No MCP server mode (gateway can't expose itself as MCP server yet)

### Priority MCP servers to build
- Chartroom (read/write/search) — replaces script-based `chart` tool, gives agents native tool access
- Agent bus (post/read inter-engine messages)
- Config reader (safe read-only config access for agents)

### Where MCP servers run
| Engine | MCP support | Config location |
|--------|------------|-----------------|
| Claude Code | `~/.claude/settings.json` mcpServers | Host |
| Gemini CLI | `~/.gemini/settings.json` mcpServers | Host |
| OpenClaw agents | `openclaw.json` agents.list[].mcp.servers | Container |
| Reactor | Inherits Claude Code's MCP config | Host |

## Rules
- Match engine to task — don't use Reactor for web research
- Free engines first — if Gemini or agents can handle it, save Reactor time
- Never block on one engine — use parallel execution when tasks are independent
