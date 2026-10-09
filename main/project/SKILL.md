---
name: project
description: APS project management — create, view, list, validate, delete, undelete, history. Template-driven, all output JSON.
tags: [project, aps, workshop, management, template]
version: 1.0.0
---

# /project — Project Management

Unified skill for all APS project operations. Used by Claude Code, Scribe, Codex, and all agents.
Every operation reads the template, enforces the standard, logs to Chartroom.

## When to use
- Creating a new project from an idea (Workshop Green Light stage)
- Viewing project identity or status
- Validating project files against the template
- Archiving (soft-deleting) a project
- Restoring an archived project
- Checking project history

## Command Grammar

```
/project create <title> [--category X] [--intent "..."] [--purpose "..."] [--engine X]
/project view <id>
/project list [--stage X] [--category X]
/project validate <id> | --all
/project touch <id> --engine <name> --action "what was done"
/project delete <id> --engine <name> [--reason "why"]
/project undelete <id> --engine <name>
/project history <id>
```

## Execution

Run the handler script directly:

```bash
python3 ~/.openclaw/scripts/project.py <subcommand> [args...]
```

## Key Rules
- **Always pass `--engine`** with your engine name (claude-code, codex, agent:scribe, etc.)
- **Delete is soft** — projects move to `.archive/`, never hard-deleted
- **All output is JSON** — machine-parseable by any engine
- **Template-driven** — reads `/root/adaptive-project-system/project-template.md` at runtime
- **Identity is stable** (top of file) — only update with human confirmation
- **Implementation is volatile** (below `---` divider) — rewrite freely

## Examples

```bash
# Create
python3 ~/.openclaw/scripts/project.py create "Voice Assistant" \
  --engine agent:scribe --category leverage \
  --intent "Hands-free system control" \
  --purpose "The ability to manage the system by voice"

# View
python3 ~/.openclaw/scripts/project.py view voice-assistant

# Validate all
python3 ~/.openclaw/scripts/project.py validate --all

# Archive
python3 ~/.openclaw/scripts/project.py delete voice-assistant \
  --engine agent:quartermaster --reason "Merged into larger project"

# Restore
python3 ~/.openclaw/scripts/project.py undelete voice-assistant --engine claude-code
```

## Files
- Script: `/root/.openclaw/scripts/project.py`
- Template: `/root/adaptive-project-system/project-template.md`
- Validator: `/root/.openclaw/scripts/validate-project.py`
- Projects: `/root/adaptive-project-system/projects/`
- Archive: `/root/adaptive-project-system/.archive/`
