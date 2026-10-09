---
name: daily-diary
description: Generate a 1-page family daily diary summarizing all system activity — wins, losses, side wins, discoveries, and insights. Delivered to Discord for Robert and Corinne. No secrets inside the family.
version: 1.0.0
author: historian
tags: [diary, daily, family, summary, nightly]
intent: Informed [I18]
---

Generate today's daily diary. Runs at 4am UTC via cron.

## Data Sources
Gather from ALL available sources:
1. **Chartroom**: charts created/updated today (`chart_search` by recent)
2. **Agent sessions**: check `sessions` MCP tool for agent activity
3. **Reactor journal**: read `/home/node/.openclaw/reactor-journal.md`
4. **Relay conversations**: what Robert and Corinne asked for today
5. **Eoin Agent**: (future) what Eoin's agent handled today
6. **Ops data**: health events, cron results, errors

## Diary Format
Write as a warm, honest 1-page family digest. Not a status report — a diary.

```
📜 Daily Diary — [date]

🏆 WINS
- [what went well, who benefited]

💔 LOSSES
- [what failed, what we learned from it]

🎯 SIDE WINS
- [unexpected good outcomes, serendipity]

🔍 DISCOVERIES
- [new knowledge, insights, things we didn't know yesterday]

💡 WHAT MAKES SENSE
- [recommendations, patterns, what the data suggests we should do]

👨‍👩‍👦 FAMILY NOTES
- [Robert's day, Corinne's day, shared context — no secrets]
```

## Output
1. Write diary to `/home/node/.openclaw/diary-latest.md`
2. Chart as `diary-YYYY-MM-DD` category `reading` importance 7
3. Send to Discord via `send_message` MCP tool to `#daily-diary` channel `1480026250645868654`
4. Email via agentToAgent to Comms Officer: send from relay.supernor@gmail.com to nowthatjustmakessense@gmail.com, subject "OpenClaw Daily Diary — [date]"
5. Keep under 2000 chars (Discord message limit friendly)

## Tone
This is a FAMILY DIARY, not a corporate status report. Write like you're telling Robert and Corinne about the day over dinner. Be warm, honest, and human. Use "we" not "the system." Celebrate small wins. Be straightforward about failures — they're how we grow. Make it something they'd actually enjoy reading.

## Rules
- No secrets inside the family — Robert and Corinne see everything
- Honest about losses — they're learning opportunities, not shame
- If Robert had a win, tell Corinne. If Corinne had a win, tell Robert.
- If nothing happened, say so — "quiet day, everything hummed along" is valid
- Future-proof: when Eoin Agent exists, include their activity too
- Keep it to ONE PAGE — if you can't say it in 2000 chars, you're overexplaining
