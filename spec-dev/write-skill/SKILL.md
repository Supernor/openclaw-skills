---
name: write-skill
description: Create or update OpenClaw skills with proper structure, testing, and documentation. Usage: /write-skill <name> <description>
version: 1.0.0
author: dev
tags: [skill, openclaw, development]
---

# write-skill

## Invoke

```
/write-skill <name> <description>       # Create a new skill
/write-skill update <name> <changes>    # Update existing skill
```

## Steps

### 1. Research
- Check if a similar skill already exists in any agent workspace
- Read the OpenClaw skill format docs at /root/openclaw/docs/tools/skills.md
- Understand what agent will own this skill

### 2. Create skill structure

Target directory: `~/.openclaw/workspace-<agent>/skills/<name>/`

Required file: `skill.md` with YAML frontmatter:
```yaml
---
name: <name>
description: <one-line description with usage>
version: 1.0.0
author: <agent-id>
tags: [relevant, tags]
---
```

### 3. Write the skill body

Every skill.md needs:
- `## Invoke` — how to call it with examples
- `## Steps` — numbered execution steps
- `## Rules` — constraints and boundaries

If the skill uses a backing script:
- `## Script` — path and usage

### 4. Register with skill router

```bash
bash ~/.openclaw/scripts/skill-router.sh build
```

### 5. Test routing

```bash
bash ~/.openclaw/scripts/skill-router.sh route "<skill keywords>"
```

### 6. Report

```
RESULT: Skill <name> created
STATUS: success
FILES: workspace-<agent>/skills/<name>/skill.md
VERIFY: skill-router.sh route "<keywords>" returns <name>
```

## Rules
- Follow existing skill patterns in the target agent workspace
- One skill per directory
- Skills are text instructions, not code libraries
- Keep skill.md under 200 lines — split complex skills into sub-skills
- Always rebuild the router index after creating/modifying skills

Intent: Growing [I09]. Purpose: [P-TBD].
