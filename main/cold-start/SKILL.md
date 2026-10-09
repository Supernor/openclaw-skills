---
name: cold-start
description: Pull core Chartroom context for session bootstrap. Zero tokens. Reads cold-start-bootstrap manifest and fetches each referenced chart.
version: 1.0.0
author: reactor
tags: [bootstrap, session, context, cold-start, chartroom]
trigger:
  command: /cold-start
  keywords:
    - cold start
    - bootstrap
    - session start
    - context load
---

# /cold-start — Session Bootstrap

Pull core Chartroom charts into context for a cold session start. Zero LLM tokens — reads charts directly via CLI.

## When to use
- Starting a new session (no prior context)
- After context compaction (lost state)
- Any time you need full situational awareness
- Debugging agent behavior (verify what context is loaded)

## Procedure

Run on HOST:
```bash
bash ~/.openclaw/scripts/cold-start.sh
```

## Output
Consolidated context block containing:
- Core charts from the bootstrap manifest (identity, config, policies, operations)
- Known Issues section from MEMORY.md

## Maintenance
- To add/remove bootstrap charts: edit CORE_CHARTS array in cold-start.sh AND update the cold-start-bootstrap Chartroom entry
- Current manifest: vision-values-harness, governance-harness-over-model, onboarding-start-here, config-model-routing, reading-youtube-transcript-pipeline, issue-youtube-cloud-ip-block, vision-transcript-api, decision-python-first, reading-use-oc-not-docker, reading-agent-communication-patterns

## Notes
- Runs on HOST only (needs chart CLI)
- Agents inside container should request via Captain or Ops Officer
- Output is designed for LLM consumption — paste into prompt context
