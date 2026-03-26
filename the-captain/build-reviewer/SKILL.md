---
name: build-reviewer
description: Review built project files for quality. Flags critical issues only.
tags: [build, review, workshop]
version: 1.0.0
---

# /build-reviewer — Review Build Quality

## When to use
- After builder creates files
- Before deployment

## Input
- Project directory with built files

## Output
- Text review: critical bugs, missing pieces, security issues (3 sentences max)

## Execution

```bash
codex-task "Review project in {dir}. Files: {file_list}. Any critical bugs or missing pieces? 3 sentences max."
```

## Rules
- Keep review short — flag blockers only, not style issues
- Codex wrapper is fine here (text in, text out — no file creation)
- Falls back to Claude if Codex auth fails

## Files
- Input: all files in `{project_dir}/`
