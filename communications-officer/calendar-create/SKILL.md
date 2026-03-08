---
name: calendar-create
description: Create a new calendar event
tags: [calendar, event, create, schedule, meeting]
---
# Calendar Create
## When to use
When scheduling a new event, meeting, or reminder.
## Execution
1. Parse: --title, --start, --end (ISO format), optional --location, --description
2. Run: `gog calendar create primary --account relay.supernor@gmail.com --title "<title>" --start "YYYY-MM-DDTHH:MM" --end "YYYY-MM-DDTHH:MM"`
3. Confirm event created with event ID and link
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log event creation via log-event

Intent: Responsive [I04]. Purpose: [P-TBD].
