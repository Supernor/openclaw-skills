---
name: gmail-draft
description: Create email draft for human review before sending
tags: [email, gmail, draft, compose, write]
---
# Gmail Draft
## When to use
Default mode for all outbound email. Creates draft for human review.
## Execution
1. Parse: --to, --subject, --body, optional --cc, --bcc, --attach
2. Run: `gog gmail draft --to "<email>" --subject "<subject>" --body "<body>"`
3. Confirm draft created, provide draft ID
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log draft creation via log-event
