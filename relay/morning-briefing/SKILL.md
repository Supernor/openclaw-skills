---
name: morning-briefing
description: Own and improve Robert's morning briefing. Pull from /api/digest (zero tokens), format compact, link to Bridge. Learn what Robert engages with vs ignores.
---

# Morning Briefing

## How It Actually Runs

The briefing is a **bash script** (`/root/.openclaw/scripts/morning-briefing.sh`) that:
1. Calls `curl http://localhost:8083/api/digest` — pre-computed summary, zero tokens
2. Formats one compact message
3. Sends via `openclaw message send` — zero tokens

**You do NOT generate the briefing.** The script does. Your job is to improve the script and the digest API over time based on what Robert engages with.

## The Rule: Point to Bridge

Telegram is a signal channel. Bridge is the detail layer.

- One line summary from /api/digest
- Decision count if any are waiting
- Error count only if > 3
- Links to Bridge sections (Board, Workshop, Feedback)
- **Never** dump task lists, idea details, or agent status in Telegram

Example output:
```
☀️ Done: 12 tasks | Active: 3 in pipeline
🔔 2 decisions waiting for you.
📋 Board: 24 ideas → bridge-url/#board
🔧 Workshop → bridge-url/#workshop
```

## Self-Learning Loop

After each briefing, track engagement:
- **Engaged:** Robert replies, follows a link, acts on a decision
- **Ignored:** No reply, pivots to unrelated topic
- Store in `memory/robert-prefs.md`
- Promote high-engagement categories, compress ignored ones
- Always include decisions waiting regardless of engagement history

## When Relay Gets Involved

The bash script handles the daily push. Relay gets involved when:
- Robert asks "what happened?" — pull /api/digest, summarize, link to Bridge
- Robert asks to change briefing content — update the script or the digest API
- Engagement data suggests a format change — propose it to Robert

## Key APIs

- `GET /api/digest` — pre-computed daily summary with counts and Board breakdown
- `GET /api/telegram/history` — see what was actually sent (for debugging)
- `GET /api/ideas` — Board state with stages
- `GET /api/tasks` — Workshop pipeline
- `GET /api/feedback` — pending decisions

All zero-token reads. Models fetch, don't generate.
