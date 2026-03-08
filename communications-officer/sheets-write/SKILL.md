---
name: sheets-write
description: Write or append data to a Google Sheets spreadsheet
tags: [sheets, spreadsheet, write, append, data]
---
# Sheets Write
## When to use
When writing new data or appending rows to a spreadsheet.
## Execution
1. Parse: sheet ID, range, values
2. Run: `gog sheets append <sheet-id> "<range>" '<values>' --account relay.supernor@gmail.com`
   - Or update: `gog sheets update <sheet-id> "<range>" '<values>' --account relay.supernor@gmail.com`
3. Confirm rows written
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log write action via log-event with row count

Intent: Competent [I03]. Purpose: [P-TBD].
