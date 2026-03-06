---
name: calendar-view
description: View upcoming calendar events and schedule
tags: [calendar, schedule, events, agenda, meetings]
---
# Calendar View
## When to use
When checking schedule, upcoming events, or availability.
## Execution
1. Parse: optional --from, --to date range, --max count
2. Run: `gog calendar list [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--max N]`
3. Format events as readable list
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log via log-event
