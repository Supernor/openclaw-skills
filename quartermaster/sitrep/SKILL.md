---
name: sitrep
description: Generate a concise system situation report (health, agent status, stale issues, pending ideas, transcript signals) and write it to /root/.openclaw/sitrep.md. Use when Reactor needs fast current-state context.
version: 1.0.0
author: quartermaster
tags: [sitrep, briefing, health, reactor]
---

Generate a current situation report and write it to `/root/.openclaw/sitrep.md`.
Keep output under 3000 characters.
Prioritize: health, active failures, stale critical charts, and top next actions.
