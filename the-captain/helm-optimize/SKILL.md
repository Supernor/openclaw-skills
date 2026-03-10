---
name: helm-optimize
description: Analyze helm usage data and optimize agent-engine routing for cost and performance
tags: [helm, routing, optimization, cost, quartermaster]
version: 1.0.0
owner: spec-quartermaster
---

# Helm Optimize

Analyze the Helm proxy usage data and recommend routing changes to minimize cost while maintaining quality.

## What the Helm Is

The Helm is a local, zero-cost OpenAI-compatible proxy on port 18791 that routes tasks to 8 engines:

| Engine | CLI | Cost | Speed |
|--------|-----|------|-------|
| ollama | ollama-task | free/local | fast |
| gemini | gemini-task | free | medium |
| openrouter | openrouter-task | free (Nemotron 30B) | fast |
| codex | codex-task | flat-rate ($20/mo) | medium |
| haiku | haiku-task | $1/$5 MTok | fast |
| nvidia | nvidia-task | per-token | fast |
| sonnet | sonnet-task | $3/$15 MTok | medium |
| opus | opus-task | $5/$25 MTok | slow |

Each of the 16 agents has a preferred engine mapped in `/root/.openclaw/helm-config.json`. The helm routes `helm/auto` calls by agent identity and walks a failover chain when engines fail.

## How to Use

Use MCP tools (works from inside container — no host paths needed):

- **Quick report**: Use `helm_report` MCP tool with `action: "report"`
- **Apply recommendations**: Use `helm_report` MCP tool with `action: "apply"`
- **Check cooldowns**: Use `helm_report` MCP tool with `action: "cooldowns"`
- **Check usage**: Use `helm_report` MCP tool with `action: "usage"`
- **Engine trust data**: Use `engine_trust` MCP tool for measured per-engine accuracy

Fallback (host only):
```bash
helm-optimize --report
helm-optimize --apply
curl -s http://localhost:18791/v1/cooldowns | python3 -m json.tool
curl -s http://localhost:18791/v1/usage | python3 -m json.tool
```

## What to Look For

1. **De-escalation signals**: If Sonnet keeps saying "route to Haiku next time," remap that agent to haiku
2. **High fail rates**: If an engine fails >40%, demote it in the failover chain
3. **Cost waste**: Agents using Sonnet/Opus for simple tasks (avg <2s response = probably too simple)
4. **Underutilized free engines**: Ollama, Gemini, OpenRouter are free — more agents should use them
5. **Failover frequency**: High failover count means the primary routing is wrong

## Optimization Cycle

Run weekly (Sunday 5am via helm-learn cron):
1. `helm-optimize --report` — review metrics
2. Identify agents whose preferred engine doesn't match their actual workload
3. `helm-optimize --apply` — apply high-confidence changes
4. Monitor for 1 week, repeat

## Files

- Config: `/root/.openclaw/helm-config.json` (agent-engine mappings, failover chain)
- Usage log: `/root/.openclaw/helm-usage.log` (every call logged with agent, engine, timing)
- Report: `/root/.openclaw/logs/helm-optimize-report.json`
- Helm server: `/usr/local/bin/helm-server` (port 18791)
- This tool: `/usr/local/bin/helm-optimize`
