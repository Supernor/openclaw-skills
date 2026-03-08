---
name: drive-search
description: Search Google Drive for files and folders
tags: [drive, files, search, documents, folders]
---
# Drive Search
## When to use
When finding files, folders, or documents in Google Drive.
## Execution
1. Parse: search query, optional --max
2. Run: `gog drive search "<query>" --account relay.supernor@gmail.com [--max N]`
   - Or browse: `gog drive ls --account relay.supernor@gmail.com [--max N]`
3. Return formatted file list with IDs and types
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log via log-event

Intent: Resourceful [I07]. Purpose: [P-TBD].
