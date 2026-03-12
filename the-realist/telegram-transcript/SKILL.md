---
name: telegram-transcript
description: View Telegram conversation history and search past messages for truth verification
tags: [telegram, transcript, history, qa, verification]
version: 1.0.0
owner: spec-realist
---

# telegram-transcript — Telegram Conversation History

## Purpose

QA and truth-verification tool. Retrieves actual Telegram conversation history from the transcript database. Used to verify claims about what was said, check message delivery, and audit conversation flow.

## Trigger

- `/transcript` — last 20 messages
- `/transcript search <keyword>` — search history
- `/transcript today` — today's messages
- `/transcript <N>` — last N messages
- "what did Robert say" / "telegram history" / "check telegram"

## Execution

Run on host via `exec`:

```bash
# Show recent messages
python3 ~/.openclaw/scripts/telegram-transcript.py show [--limit N] [--after DATE] [--before DATE]

# Search messages
python3 ~/.openclaw/scripts/telegram-transcript.py search "keyword" [--limit N]

# Statistics
python3 ~/.openclaw/scripts/telegram-transcript.py stats

# Machine-readable
python3 ~/.openclaw/scripts/telegram-transcript.py show --json
```

## Data Source

SQLite DB at `/root/.openclaw/telegram-transcript.db`. Fed by:
- **telegram-listener** (tmux daemon, real-time)
- **backfill** (one-time historical import from session JSONL)

## Truth Verification Uses

- "Did Robert say X?" → search for it
- "When was the last message?" → show --limit 1
- "Was the chain test delivered?" → search "chain test"
- "How many messages today?" → stats

intent: Trusted [I11], Informed [I07]
