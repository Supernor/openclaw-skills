---
name: telegram-transcript
description: View Telegram conversation history and search past messages
tags: [telegram, transcript, history]
version: 1.0.0
owner: relay
---

# telegram-transcript

## Trigger
- `/transcript`
- `/transcript search <keyword>`
- `/transcript today`
- `/transcript <N>`
- "show transcript", "telegram history", "what did I say"

## Execution

```bash
# Last 20 messages
python3 ~/.openclaw/scripts/telegram-transcript.py show

# Last N messages
python3 ~/.openclaw/scripts/telegram-transcript.py show --limit N

# Search
python3 ~/.openclaw/scripts/telegram-transcript.py search "keyword"

# Today only
python3 ~/.openclaw/scripts/telegram-transcript.py show --after "YYYY-MM-DD"

# Stats
python3 ~/.openclaw/scripts/telegram-transcript.py stats
```

Self-contained. No Captain dispatch needed.
