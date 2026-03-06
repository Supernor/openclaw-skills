---
name: sheets-read
description: Read data from a Google Sheets spreadsheet
tags: [sheets, spreadsheet, read, data, google-sheets]
---
# Sheets Read
## When to use
When reading spreadsheet data — full sheet or specific range.
## Execution
1. Parse: sheet ID and optional --range (e.g., "A1:Z100")
2. Run: `gog sheets get <sheet-id> [--range "A1:Z100"]`
3. Format data as readable table
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log via log-event
