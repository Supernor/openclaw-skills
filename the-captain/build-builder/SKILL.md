---
name: build-builder
description: Build project files from architecture. Reads architecture.md + project.md, creates all files.
tags: [build, builder, workshop]
version: 1.0.0
---

# /build-builder — Build Project Files

## When to use
- After architecture.md exists in the project directory
- When you need to create all implementation files

## Input
- Project directory containing architecture.md + project.md

## Output
- All project files created in the directory

## Execution

```bash
cd {dir} && npx @openai/codex exec --full-auto --skip-git-repo-check \
  "Read architecture.md and project.md. Build all files needed for a working project. Include a /healthz endpoint if web."
```

## Rules
- Use Codex --full-auto directly (NOT codex-task wrapper — it breaks on builds)
- Codex reads the files in the directory — don't repeat their content in the prompt
- Short prompt: tell Codex WHAT to do, let it read HOW from the files
- Check for new files after completion (exit code may be non-zero even on success)

## Files
- Input: `{project_dir}/architecture.md`, `{project_dir}/project.md`
- Output: all files listed in architecture.md
