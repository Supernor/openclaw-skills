---
name: validate-idea
description: Pre-validate a proposed idea against our actual architecture and capabilities
tags: [validate, idea, feasibility, check, architecture, capability, blockers]
version: 1.0.0
---

# /validate-idea — Idea Feasibility Check

Check whether a proposed idea can actually be built with what we have.

## When to use
- Before presenting ideas to Robert
- "Can we actually build [idea]?"
- "What's blocking [idea_id]?"
- After proposing new ideas to the pipeline

## Execution
```bash
strategist validate-idea <idea_id>
```

## Checks
- VPS hosting, Docker, cron, agents
- API access (Codex, Gemini, OpenRouter)
- Discord, GitHub integration
- Missing capabilities: payment processing, public API, domain, email, SSL

## Output
Capability matrix with YES/NO + blocker list.
Blockers tell Robert exactly what needs setup before an idea can launch.

Intent: Competent [I05]. Purpose: Prevent wasted effort on unbuildable ideas.
