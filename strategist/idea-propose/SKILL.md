---
name: idea-propose
description: Scan sources and propose scored ideas to the pipeline for Robert's review
tags: [idea, propose, opportunity, revenue, cashflow, pipeline, scan, unmanned]
version: 1.0.0
---

# /idea-propose — Propose Ideas to Pipeline

Scan transcript library, Chartroom, or web intelligence and auto-submit scored ideas.

## When to use
- "Find opportunities in the transcripts"
- "Scan for cashflow ideas"
- "What unmanned revenue can we build?"
- After ingesting new transcript content
- Periodic opportunity sweeps

## Process
1. Generate ideas as JSON (from scan, analysis, or research delegation)
2. Write to temp file: `workspace/memory/proposed-ideas.json`
3. Submit: `strategist idea-propose proposed-ideas.json`
4. Ideas land as "proposed" — Robert reviews via `idea top`

## Constraints
- UNMANNED ONLY: every idea must pass "can this make money while Robert sleeps?"
- Robert has a full-time day job — no consulting, no client calls, no manual delivery
- Score honestly: impact 1-5, effort 1-5 (5=easiest), urgency 1-5
- Minimum score threshold to propose: 27 (3x3x3)

## Output
Ideas appear in pipeline. Run `idea top` or `idea stats` to verify.

Intent: Resourceful [I07]. Purpose: Revenue pipeline automation.
