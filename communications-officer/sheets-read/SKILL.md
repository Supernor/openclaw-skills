---
name: sheets-read
description: Read data from a Google Sheets spreadsheet
tags: [sheets, spreadsheet, read, data, google-sheets]
---
# Sheets Read
## When to use
When reading spreadsheet data — full sheet or specific range.
## Execution
1. Parse: sheet ID and range (e.g., "Sheet1!A1:Z100")
2. Run: `gog sheets get <sheet-id> "<range>" --account relay.supernor@gmail.com`
3. Format data as readable table
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log via log-event
