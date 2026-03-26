---
name: tool-audit
description: Audit and update all agent TOOLS.md files for MCP tool awareness. Self-improving — learns from each run.
version: 1.0.0
author: captain
tags: [nightly, school, tools, mcp, audit]
---

# tool-audit — MCP Tool Awareness Audit

## Purpose

Ensure every agent in the fleet knows about their available MCP tools. Agents that don't know their tools can't use them — this causes failures like "chart write blocked" when the tool actually works fine.

## When to Run

- Every nightly school session (automatic)
- When an agent reports "I don't have access to X"
- When a new MCP tool is added to the gateway
- On demand via `/tool-audit`

## Procedure

### Step 1: Get current tool inventory

Call the `capabilities` MCP tool to get the full grouped tool list. This is the source of truth.

### Step 2: Audit each agent workspace

For each agent in the fleet:
1. Read their `TOOLS.md` file
2. Check if these CORE tools are documented:
   - `chart_search` (Chartroom search)
   - `chart_add` (Chart new entries)
   - `ops_insert_task` (Create tasks — MANDATORY before delegation)
   - `capabilities` (Self-discovery)
   - `ops_query` (Read ops.db)
3. Check if they reference `docs/mcp-tools-reference.md`

### Step 3: Fix gaps

For any agent missing core tools:
1. Add the MCP Tools section to their TOOLS.md
2. Include at minimum: chart_search, chart_add, ops_insert_task, capabilities, ops_query
3. Add pointer to `docs/mcp-tools-reference.md` for the full list
4. Keep the additions concise — agents need tool NAMES, not essays

### Step 4: Verify

After updates, for each agent updated:
1. Call `ask_agent` with message "What MCP tools do you have? Call capabilities to check."
2. Verify the agent can discover its own tools
3. If it still claims ignorance, the TOOLS.md needs stronger wording

### Step 5: Record findings

Chart the audit results:
```
chart_add("tool-audit-YYYY-MM-DD", "Audited N agents. X had full tool awareness, Y needed updates. Fixed: [list]. Still struggling: [list].", "procedure", 0.85)
```

## Self-Improvement

After each run, note:
- Which agents needed fixes (pattern = they keep losing tool awareness after session resets)
- Which tools agents fail to discover on their own
- Whether `capabilities` call works reliably for self-discovery
- Update this skill with new patterns found

## Reference

Full MCP tool inventory: `docs/mcp-tools-reference.md`

## Rules

- Never remove existing TOOLS.md content — only ADD missing tools
- Keep additions concise — tool name + one-line description
- Always include the `capabilities` self-discovery escape hatch
- Chart every run for historical tracking
