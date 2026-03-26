---
name: build-architect
description: Design project architecture from specs. Reads project.md, writes architecture.md.
tags: [build, architect, workshop]
version: 1.0.0
---

# /build-architect — Design Project Architecture

## When to use
- At the Build stage when a project needs an implementation design
- When you have a project.md with specs but no architecture.md yet

## Input
- Project directory containing project.md with filled Identity section

## Output
- architecture.md written to the same directory
- Contains: file list, dependencies, key decisions, deployment notes

## Execution

From Claude (preferred):
```bash
claude -p "You are an architect. Read project.md in {dir}. Design: file list with purpose, dependencies, deployment strategy. Keep it concise and buildable." --output-format text > {dir}/architecture.md
```

From Codex (failover):
```bash
codex-task "Read project.md in {dir}. Design the architecture: file list, dependencies, key decisions. Output as markdown."
```

## Rules
- Read project.md directly — don't ask for specs in the prompt
- Output must be actionable by the builder (file names, not abstractions)
- Keep under 2000 chars — the builder reads this, not a human

## Files
- Output: `{project_dir}/architecture.md`
