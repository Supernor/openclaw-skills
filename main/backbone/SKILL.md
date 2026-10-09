---
name: backbone
description: Monitor agent backbone activity — zero tokens, reads SQLite directly. Shows inter-agent messages, task queue, reactor jobs, and gateway logs.
tags: [backbone, monitor, agents, ops, tasks, reactor, zero-token]
version: 1.0.0
---

# /backbone — Agent Backbone Monitor

Zero-token listener for all agent communication. Reads ops.db + reactor-ledger.sqlite + gateway docker logs directly. No LLM calls.

## When to use
- Check what agents are doing right now
- Monitor task handoffs and completions
- Debug agent communication issues
- Watch for errors, rate limits, or failures
- Verify a task you dispatched was received

## Command Grammar

```
/backbone                    — Show listener status
/backbone snapshot           — One-time dump of recent backbone activity
/backbone start              — Start persistent listener (tmux background)
/backbone stop               — Stop persistent listener
```

## Execution

Run on the HOST (not in container):

```bash
backbone status              # Is listener running?
backbone snapshot            # What happened recently?
backbone start               # Start persistent monitor
backbone stop                # Stop it
```

Or directly:
```bash
python3 ~/.openclaw/scripts/backbone-listener.py --once    # Single check
python3 ~/.openclaw/scripts/backbone-listener.py           # Continuous
```

## What it monitors

| Source | Data | Update rate |
|--------|------|-------------|
| ops.db `agent_results` | Inter-agent messages (handoffs, results) | On event |
| ops.db `tasks` | Task queue (pending, in_progress, completed) | On event |
| ops.db `notifications` | System alerts (failures, recoveries) | On event |
| reactor-ledger `jobs` | Reactor work items and status changes | On event |
| reactor-ledger `events` | Reactor lifecycle events | On event |
| reactor-ledger `questions` | Reactor questions waiting for answers | On event |
| Gateway docker logs | Agent conversation output, errors, plugin events | Real-time |

## Output format

```
HH:MM:SS       source | event details
21:40:19        agent | backbone test confirmed
21:38:29      gateway | [plugins] error: rate limit exceeded
21:29:28         task | pending -> completed [reactor] Build generate-memory.py
```

## Notes

- Runs on HOST only (needs docker + SQLite access)
- Agents inside the container should request this via Captain or Ops Officer
- The persistent listener runs in tmux session "backbone"
- To attach: `tmux attach -t backbone`
- Zero LLM tokens — pure SQLite polling + docker log tailing
