---
name: generate-memory
description: Regenerate MEMORY.md from Chartroom charts via template. Resolves chart placeholders, enforces 200-line cap.
version: 1.0.0
author: reactor
tags: [memory, MEMORY.md, chartroom, template, regenerate]
trigger:
  command: /generate-memory
  keywords:
    - generate memory
    - regenerate memory
    - rebuild memory
    - memory from charts
---

# /generate-memory — Rebuild MEMORY.md from Charts

Regenerate MEMORY.md by reading memory-template.md and resolving all {{chart:ID}} placeholders via chart read. Ensures output stays under 200 lines.

## When to use
- After updating charts referenced in MEMORY.md
- After adding new {{chart:ID}} placeholders to the template
- Periodically to keep MEMORY.md fresh with latest chart content
- After any session where charts were modified

## Procedure

Run on HOST:
```bash
python3 ~/.openclaw/scripts/generate-memory.py
```

## How it works
1. Reads template: ~/.openclaw/scripts/memory-template.md
2. Finds all {{chart:ID}} placeholders
3. Resolves each by running chart read ID (skips metadata, extracts body)
4. Writes output to /root/.claude/projects/-root/memory/MEMORY.md
5. Truncates at 200 lines if exceeded
6. Verifies cold-start-bootstrap reference is present

## Template syntax
```
## Section Header
{{chart:my-chart-id}}
Static content that stays as-is.
```

## Current placeholders (6)
- config-model-routing
- governance-known-issues-openclaw-installation-v1
- issue-youtube-cloud-ip-block
- decision-python-first
- vision-transcript-api
- plan-next-session-2026-03-07

## Notes
- Template is the source of truth — edit it, not MEMORY.md directly
- MEMORY.md is a generated artifact (will be overwritten on next run)
- To add a chart to MEMORY.md: edit memory-template.md, add {{chart:your-id}}
- Runs on HOST only (needs chart CLI + Python3)
