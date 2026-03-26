---
name: build-mediator
description: Orchestrate build steps. Mistral assesses, dispatches experts, narrates to human, tracks in ops.db.
tags: [build, orchestrate, workshop, mediator]
version: 1.0.0
---

# /build-mediator — Orchestrate a Project Build

## When to use
- When a Workshop idea reaches Build stage
- Triggered by tap-daemon.py on "Start Build" button

## Input
- idea-id, chat-id, topic-id

## Output
- Built project with test link (if deployable)
- ops.db tasks for each step (backbone visibility)
- Telegram narration at each step

## Execution

```bash
python3 /root/.openclaw/scripts/build-engine.py --idea-id {id} --chat-id {chat} --topic-id {topic}
```

## Steps
1. **Assess** (Mistral, <256 tokens) — what type of project?
2. **Architect** (Claude/Codex) — read project.md, write architecture.md
3. **Build** (Codex --full-auto) — read architecture.md, create all files
4. **Review** (Codex) — flag critical issues
5. **Deploy** (local script) — detect type, serve, return URL
6. **Summarize** (Mistral, <256 tokens) — 3 sentences for the human

## Rules
- Each step is an ops.db task (agent: "workshop-build")
- Narrate to Telegram BEFORE each step starts (say what you're doing before you do it)
- Mistral outputs under 256 tokens during orchestration — he decides, doesn't compose
- Agents read files directly — don't stuff context into prompts
- Codex build uses npx directly, NOT codex-task wrapper
- Dynamic config: VPS_IP, ports, model names from env, not hardcoded

## Files
- Script: `/root/.openclaw/scripts/build-engine.py`
- Deploy: `/root/.openclaw/scripts/deploy-project.py`
- Skills: `/root/.openclaw/workspace/skills/build-*/SKILL.md`
