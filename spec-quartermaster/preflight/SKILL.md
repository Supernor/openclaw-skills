---
name: preflight
description: Build pre-session context showing what changed since last session, including new charts, alerts, and notable agent/system activity. Use at session start before substantive work.
version: 1.0.0
author: quartermaster
tags: [preflight, delta, session, context]
intent: Observable [I04]
---

Compute a preflight delta since last session.
Summarize only high-impact changes and blockers.
Output a short briefing suitable for immediate action.
