---
name: reactor
description: Route coding and engineering tasks to Claude Code (the Reactor) via the bridge
tags: [coding, debugging, engineering, bridge, reactor]
version: 1.0.0
---

# Reactor — Claude Code Bridge

Route coding, debugging, and engineering tasks to the Reactor (Claude Code on the host).

## When to use
- Code changes that need file edits, debugging, or system work
- Tasks too complex for impulse-tier agents
- Anything requiring access to host files, Docker config, or the OpenClaw codebase

## How it works
The Reactor is Claude Code running on the host. It has full access to the OpenClaw deployment, configs, scripts, and codebase. Tasks are sent via the bridge — a file-based handoff.

## Usage

Send a task:
```bash
bash: ~/.openclaw/scripts/bridge.sh send "reactor" "Fix the webhook handler" --priority normal --desc "The handler at scripts/webhook.sh is returning 500 on POST requests. Error in logs: permission denied on /tmp/webhook.lock"
```

Check if the reactor has finished:
```bash
bash: ~/.openclaw/scripts/bridge.sh status
```

## Parameters
- **subject**: Short task title (required)
- **--desc**: Full description with context, error messages, file paths (required for good results)
- **--priority**: `low`, `normal`, `high`, `urgent`
- **--files**: JSON array of relevant file paths

## After Sending a Task

1. Tell Captain/Relay: "Reactor task submitted — check #ops-reactor for progress."
2. The reactor streams progress markers to #ops-reactor as it works.
3. When the reactor finishes, it posts a completion embed to #ops-reactor.
4. On your next heartbeat, check results: `bridge.sh check <your-agent-id>`
5. Read the result from the outbox and relay it back through Captain.

Do NOT poll in a tight loop. The reactor posts progress to Discord — Robert can watch there.

## Task Scoping

Claude Code works best with focused, well-scoped tasks. Follow these guidelines:
- Each task should be completable in **~10 minutes**.
- If a task needs 30+ minutes of work, **split it into 3+ sequential tasks** with clear inputs/outputs.
- Include enough context so the reactor doesn't have to discover things from scratch.
- Always include: error messages, file paths, what you've already tried, what the expected outcome is.

Bad: "Fix everything in the relay workspace"
Good: "Fix the embed color in /root/.openclaw/workspace-relay/scripts/post-status.sh — currently sends 0x000000 (black), should use 0x58B9FF (brand blue)"

## Autonomy Policy

The Reactor operates under a confidence-based autonomy policy:

1. **No direct human contact.** The Reactor never asks the human (Robert) for clarification directly. If it needs more info, it returns a clarification question as its result — you (the requesting agent) relay it.
2. **High confidence + reversible = auto-proceed.** If the Reactor is >=80% confident and the action is reversible (file edits, reads, non-destructive commands), it proceeds without asking.
3. **Low confidence or irreversible = stop and ask.** If confidence is <80% or the action is hard to reverse (force-push, config overwrite, infra change), the Reactor stops and returns one concise clarification question.
4. **Serialized lane.** One task at a time: request -> result -> next request. Don't batch multiple tasks into one send.

**What this means for you:** If you get a clarification question back instead of a result, answer it and re-send the task with the additional context.

## Tips
- Be specific. Include error messages, file paths, and what you've already tried.
- The reactor works from `/root/.openclaw/` — use paths relative to that or absolute paths.
- The reactor has unlimited power (flat-rate plan) — don't hesitate to send complex tasks.
- The reactor can search the Chartroom for known fixes before debugging from scratch.
- Results include a duration field so you can gauge how long similar tasks take.

## Example tasks
- "Debug why model-health-monitor isn't posting to ops-alerts"
- "Write a new skill for the Scribe agent that summarizes GitHub PRs"
- "Fix the Discord embed formatting in the relay workspace"
- "Create a deployment script for static sites"
