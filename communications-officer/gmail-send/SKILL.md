---
name: gmail-send
description: Send email directly — requires explicit send authorization
tags: [email, gmail, send, outbound]
---
# Gmail Send
## When to use
ONLY when requesting agent has explicit "send" authorization. Default to gmail-draft otherwise.
## Execution
1. Verify explicit send authorization from requesting agent
2. If not authorized, create draft instead (gmail-draft)
3. Parse: --to, --subject, --body
4. Run: `gog gmail send --account relay.supernor@gmail.com --to "<email>" --subject "<subject>" --body "<body>"`
5. Confirm sent, return message ID
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log every sent email via log-event with full details
