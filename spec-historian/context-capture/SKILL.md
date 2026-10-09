---
name: context-capture
description: Capture a structured context snapshot for the Black Box system. Gathers recent charts, agent sessions, health events, ops activity, and taint status into a single snapshot charted for future recovery.
version: 1.0.0
author: historian
tags: [context, snapshot, recovery, black-box, preservation]
intent: Recoverable [I15]
---

Capture a structured context snapshot.

1. Gather data from all available sources:
   - **Recent charts**: Use `chart_search` for entries from today or the last 24h
   - **Agent sessions**: Use `sessions_list` to see active sessions and context usage
   - **Health events**: Use `health` MCP tool for system status
   - **Backbone activity**: Use `backbone_snapshot` for recent agent_results, tasks, notifications
   - **Reactor journal**: Read `/home/node/.openclaw/reactor-journal.md`

2. Synthesize into a structured snapshot:
   - **Key decisions** made since last snapshot
   - **Work in progress** — what's active, what's blocked
   - **Discoveries** — new knowledge, bugs found, insights
   - **Agent observations** — which agents ran, what they produced, any failures
   - **Trust signals** — what worked well, what failed

3. Chart as `context-snapshot-YYYY-MM-DDTHH` with category `reading` and importance 7

4. Keep chart text under 500 chars — summary only. Write full snapshot to `/home/node/.openclaw/context-snapshot-latest.md`

Use this skill when:
- Called by cron (periodic snapshots)
- Called by Reactor before a large operation
- Called by any agent that wants to checkpoint system state
- Called by SessionEnd hook for end-of-session archival
