---
name: contacts-search
description: Search Google Contacts for people and contact info
tags: [contacts, people, search, address-book]
---
# Contacts Search
## When to use
When looking up contact information — phone, email, address.
## Execution
1. Parse: search query (name, email), optional --max
2. Run: `gog contacts list [--query "name"] [--max N]`
3. Return formatted contact list
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log via log-event
