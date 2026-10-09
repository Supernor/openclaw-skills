---
name: session-archive
description: Archive a Reactor session journal into a structured Chartroom entry. Read reactor-journal.md, extract decisions/discoveries/WIP, chart as session-journal-YYYY-MM-DD.
version: 1.0.0
author: historian
tags: [session, archive, journal, history]
intent: Informed [I18]
---

Archive the current Reactor session journal.

1. Read `/home/node/.openclaw/reactor-journal.md`
2. Extract: session date, decisions made, discoveries, work completed, uncharted insights
3. Chart as `session-journal-YYYY-MM-DD` with category `reading`, importance 8
4. Keep chart text under 500 chars — summary, not full transcript
5. Update MEMORY.md session archive index
6. If journal has COMPACTION markers, note how many compactions occurred
