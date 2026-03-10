---
name: fleet-health
description: One-page fleet overview — system status, Helm routing, satisfaction scores.
version: 1.0.0
author: captain
tags: [fleet, health, overview, status]
intent: Reliable [I05]
---

# fleet-health

Produce a one-page fleet state summary.

## Trigger
`/fleet-health`

## Process

1. Call `system_status` — gateway health, disk usage, memory, Ollama status.
2. Call `provider_health` — which API providers are reachable, latency, cooldowns.
3. Call `helm_report` — routing state, active cooldowns, recent errors.
4. Call `satisfaction_scores` — fleet average, bottom 3 agents, any alerts.
5. Combine into a single-page summary.

## MCP Tools Used
- `system_status` — Infrastructure health
- `provider_health` — API provider reachability + cooldowns (zero tokens, ~1s)
- `helm_report` — Engine routing state
- `satisfaction_scores` — Agent satisfaction data

## Output Format
```
# Fleet Health — [date]

## Infrastructure
- Gateway: [status]
- Disk: [usage]
- Memory: [usage]
- Ollama: [status]

## Providers
- Anthropic: [reachable/down] [latency] [cooldown or "ok"]
- Google: [reachable/down] [latency] [cooldown or "ok"]
- OpenAI: [reachable/down] [latency] [cooldown or "ok"]

## Routing
- Engines: [count active]
- Cooldowns: [list or "none"]
- Recent errors: [count or "none"]

## Satisfaction
- Fleet avg: XX/100
- Bottom 3: [agent: score, ...]
- Alerts: [list or "none"]

## Action needed
- [prioritized list or "Fleet healthy"]
```
