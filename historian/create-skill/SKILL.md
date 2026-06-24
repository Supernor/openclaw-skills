---
name: create-skill
description: Create a new OpenClaw skill following the system's best practices. Produces well-documented, self-teaching skills that any agent (or Claude Code) can execute without prior context.
version: 1.0.0
tags: [meta, skill-creation, templates, best-practices]
---

# Create Skill

## Purpose
Create a new skill that follows our proven patterns. A skill is a SKILL.md
file that teaches an agent what to do — it's a recipe card, not a program.
The actual work happens via bash scripts, tools, or the agent's own reasoning.

## When to use
- You need to create a new repeatable workflow for an agent
- An existing process should be formalized so it's not lost when a session ends
- A task keeps being done ad-hoc that should be standardized
- Robert asks for a skill, or you discover a workflow that should be reusable

## Core principle: Skills teach agents, not humans

Every skill will be read by an LLM with ZERO context about this system.
The skill must contain everything the agent needs to execute it correctly,
including why things are done a certain way. If you remove all other context
and hand someone just the SKILL.md, they should be able to execute it.

## Skill anatomy

Every skill lives in a directory: `workspace-<agent>/skills/<skill-name>/SKILL.md`

Shared skills go in `/root/.openclaw/skills/<skill-name>/SKILL.md` and are
symlinked into each agent's workspace that needs them:
```bash
ln -sf /root/.openclaw/skills/<skill-name> /root/.openclaw/workspace-<agent>/skills/<skill-name>
```

## Template

Use this structure. Every section exists for a reason — don't skip them.

```markdown
---
name: <skill-name>
description: <one line — what this skill does, specific enough to match in skill-router search>
version: 1.0.0
author: <agent-name>
tags: [<relevant>, <searchable>, <keywords>]
---

# <Skill Name>

## Purpose
<2-3 sentences: What does this skill accomplish? Why does it exist?
Write this for an agent who has never seen this system before.>

## When to use
<Bullet list of specific triggers. Be concrete:>
- When Robert asks "..."
- When cron dispatches this task
- After an OpenClaw update
- When <specific error> appears in logs

## Steps

### Phase 1: <Name>
<Instructions the agent follows. Use code blocks for commands.>

```bash
<exact command to run>
```

<After each command, explain what to do with the output:>
- **If <good result>**: <what to do next>
- **If <bad result>**: <what this error means and how to fix it>
  ERROR MEANING: <explain what's actually broken, not just what the error says>
  HISTORY: <when this happened before and what fixed it>
  FIX: <specific steps>

### Phase 2: <Name>
<Continue with more steps...>

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| <error text> | <root cause> | <specific fix steps> |

## Related
- `/other-skill` — <how it relates>
- `chart read <chart-id>` — <what context it provides>
- `chart search "<keywords>"` — <what to search for>

## Notes
<Anything the agent needs to know that doesn't fit above.
Include warnings about common mistakes.>

Intent: <which system intent this serves>
```

## Best practices (learned the hard way)

### 1. Error messages teach the agent, not just report status

BAD:
```
Error: push failed
```

GOOD:
```
Error: push failed
ERROR MEANING: Git authentication with GitHub failed. The credential helper
  may point to a dead binary path (common after container rebuilds).
HISTORY: This broke on 2026-05-10 after the v2026.5.8 update rebuilt the image.
FIX: Run `/github-guardian` to repair the credential helper.
WHAT HASN'T BEEN TRIED: Checking if GH_TOKEN env var is present.
```

### 2. Scripts do the work, skills interpret the results

Skills should NOT contain complex bash logic. If you need more than 5 lines
of bash, create a script at `/root/.openclaw/scripts/<name>.sh` and have
the skill invoke it. Scripts are:
- Testable independently (`bash -n` for syntax, direct execution for testing)
- Zero tokens (no LLM needed to run them)
- Reusable by crons and other skills

The skill's value is in INTERPRETING results, DIAGNOSING failures, and
DECIDING what to do next.

### 3. Include the "why" alongside the "what"

BAD:
```bash
chown 1000:1000 /root/.openclaw/openclaw.json
```

GOOD:
```bash
# Fix file permissions — host-side edits (Claude Code, sed, etc.) change
# owner to root, but the container runs as node (uid 1000). Without this,
# the gateway gets EACCES on startup and logs a misleading "gateway.mode
# missing" error (the file can't be read at all, not just missing that key).
chown 1000:1000 /root/.openclaw/openclaw.json
```

### 4. Reference charts for deeper context

Don't duplicate operational knowledge that's already charted. Point to it:
```
chart read <chart-id>    # Specific chart
chart search "<query>"   # Find related charts
```

Charts survive session boundaries. Skills should reference them so agents
can get historical context without the skill becoming a novel.

### 5. Show the agent what success looks like

Always include expected output format so the agent can verify its work:
```
Expected: {"status":"PASS","pushed":true}
If you see: {"status":"ERROR",...} — see Error diagnosis
```

### 6. Coordinator skills chain individual skills

For multi-step workflows, create a coordinator skill that runs individual
skills in sequence. The coordinator handles:
- Preflight checks (prerequisites)
- Running each sub-skill
- Aggregating results
- Deciding whether to continue or escalate

Example: `/backup-suite` coordinates `/env-backup`, `/skills-backup`, `/workspace-backup`

### 7. Include "After an OpenClaw update" section

Many skills break after updates (paths change, plugins externalize, models
deprecate). Include a section explaining what to check post-update.

### 8. Version your skills

Increment the version in frontmatter when you make meaningful changes.
This helps track which version of a skill is deployed where.

## Pattern: Wrapping an existing script as a skill

Many capabilities already exist as bash scripts in `/root/.openclaw/scripts/`.
A skill adds **discoverability** (agents know it exists), **teaching** (agents
know when and how to use it), and **error interpretation** (agents handle failures).

### When to use this pattern
- A script exists but agents don't know about it or use wrong syntax
- The script works on host AND in container (bind-mounted paths)
- You want multiple agents to discover the capability via skill-router

### Template for script-wrapper skills

```markdown
## How to invoke

Use the `exec` tool. The script is in the gateway's exec path (`~/.openclaw/scripts/`):

\`\`\`bash
exec <script-name>.sh <subcommand> [args...]
\`\`\`

**Do NOT** use `bash`, `sh`, or full paths. The exec tool resolves the script
from pathPrepend automatically.

## Available commands

| Command | Args | Output | Example |
|---------|------|--------|---------|
| list    | none | TSV rows | `exec myscript.sh list` |
| get     | `<id>` | JSON/text | `exec myscript.sh get abc-123` |

## Navigating hierarchical data

<If the script navigates a tree (notebooks→sections→pages, drives→folders→files):>

1. Start by listing the top level: `exec script.sh list-top`
2. Pick the ID from the output (first column, tab-separated)
3. Drill down: `exec script.sh list-children <id-from-step-1>`
4. Read the item: `exec script.sh read <id-from-step-2>`

**The IDs are opaque strings** — don't guess them, always get them from
the previous command's output.
```

### Key rules for script-wrapper skills
1. **Tell the agent which tool to use** — `exec`, not `bash` or raw subprocess
2. **Show the exact command syntax** — agents can't read script help text on their own
3. **Document the output format** — TSV, JSON, HTML, plain text?
4. **Map the navigation tree** — if the script has hierarchical data, show the drill-down sequence
5. **Include known IDs** — if there's only one notebook or a known section, hardcode it to save round trips
6. **Auth errors are the #1 failure** — always document what token expired means and how to fix it

## Pattern: Tool invocation (exec, MCP, or host-ops)

Different capabilities use different invocation methods. The skill MUST tell
the agent which one:

| Method | When to use | Syntax in skill |
|--------|-------------|-----------------|
| `exec` tool | Script in container's pathPrepend | `exec script.sh args` |
| MCP tool | Plugin-provided capability | `mcp__plugin__tool_name(params)` |
| `ops_insert_task` | Host-side work via executor | `ops_insert_task(host_op='handler-name', ...)` |
| `sessions_spawn` | Delegate to another agent | `sessions_spawn(agent='spec-dev', message='...')` |

Always specify the method. Agents should never have to guess whether to use
exec, MCP, or task dispatch.

## After creating the skill

1. **Test it**: Have the owning agent execute it once and verify the output
2. **Chart it**: `chart add "skill-<name>" "<description>" "skill" 0.85`
3. **Symlink if shared**: Link into each workspace that needs it
4. **Update AGENTS.md**: Add the skill to the agent's skill table
5. **Skills-backup**: Run `/skills-backup` so it's preserved on GitHub

## Where skills live

| Scope | Path | Who uses it |
|-------|------|-------------|
| Agent-specific | `workspace-<agent>/skills/<name>/` | Just that agent |
| Shared | `/root/.openclaw/skills/<name>/` | Multiple agents via symlinks |
| Captain (main) | `workspace/skills/<name>/` | Captain + any agent that inherits |

## Naming conventions
- Lowercase, hyphen-separated: `backup-suite`, `channel-health`, `create-skill`
- Action-first when possible: `send-discord`, `rotate-key`, `validate-idea`
- Skills that coordinate others: name after the workflow, not the steps
