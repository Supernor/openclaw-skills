---
name: calendar-update
description: Update an existing calendar event
tags: [calendar, event, update, modify, reschedule]
---
# Calendar Update
## When to use
When modifying time, title, location, or details of an existing event.
## Execution
1. Parse: event-id and fields to update (--title, --start, --end, --location)
2. Run: `gog calendar update primary <event-id> --account relay.supernor@gmail.com [flags]`
3. Confirm update applied
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log event update via log-event

Intent: Responsive [I04]. Purpose: [P-TBD].
