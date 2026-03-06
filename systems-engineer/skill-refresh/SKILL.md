---
name: skill-refresh
description: Audit and update skills against current OpenClaw capabilities, GitHub changes, and MCP ecosystem
tags: [skills, maintenance, updates, mcp, self-improvement]
version: 1.0.0
---

# Skill Refresh

Skills go stale. OpenClaw updates, MCP ecosystem evolves, new CLI commands appear. This skill audits and updates other skills to stay current.

## When to use
- After OpenClaw updates (`oc update`)
- Periodically (weekly or after major changes)
- When a skill fails or feels outdated
- After Research Agent surfaces new capabilities

## Process

### Step 1: Discover what changed
```bash
# Check OpenClaw version and available commands
oc --version
oc commands

# Check for new/changed CLI commands
oc --help 2>/dev/null | diff - /root/.openclaw/last-cli-snapshot.txt || true

# Check GitHub for recent changes (via Research Agent)
oc agent --agent spec-research --message "Check OpenClaw GitHub for recent PRs and releases affecting CLI commands, MCP support, skills, or plugins. Focus on changes since our version 2026.3.3." --json --timeout 120

# Snapshot current CLI for next comparison
oc --help > /root/.openclaw/last-cli-snapshot.txt 2>/dev/null
```

### Step 2: Audit existing skills
```bash
# List all skills across all workspaces
find /root/.openclaw/workspace*/skills -name "SKILL.md" -exec grep -l "version:" {} \;

# Check each skill for:
# - Commands that no longer exist
# - Missing new capabilities that fit the skill's purpose
# - Outdated version references
# - MCP alternatives that could replace script-based approaches
```

### Step 3: Update skills
For each outdated skill:
1. Read the current SKILL.md
2. Check `oc <relevant-command> --help` for current options
3. Update the skill with new/changed commands
4. Bump the version number

### Step 4: Check MCP ecosystem
```bash
# Research Agent: scan for new MCP servers relevant to our setup
oc agent --agent spec-research --message "Search for MCP servers relevant to: Chartroom/LanceDB, Discord, GitHub, security scanning, cron/scheduling. What's available on npm or GitHub that we could plug into OpenClaw's mcp-bridge?" --json --timeout 120
```

### Step 5: Report and chart
```bash
chart add "skill-refresh-<date>" "Refreshed N skills. Changes: [list]. New MCP servers found: [list]. Next refresh recommended: [date]." "reading" 0.8
```

## What to watch for
- New `openclaw` subcommands (compare --help output)
- MCP servers that replace manual scripts
- Deprecated commands or flags
- New plugin capabilities
- GitHub PRs tagged with `skill`, `mcp`, `cli`, or `plugin`
