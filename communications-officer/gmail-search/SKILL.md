---
name: gmail-search
description: Search Gmail messages by query, sender, date, or label
tags: [email, gmail, search, messages, inbox]
---
# Gmail Search
## When to use
When any agent or human needs to find emails — by keyword, sender, date range, or label.
## Execution
1. Parse request for: query terms, --from, --to, --after, --before, --label, --max
2. Run: `gog gmail search "<query>" [flags]`
3. Return formatted results to requesting agent
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log every search via log-event
