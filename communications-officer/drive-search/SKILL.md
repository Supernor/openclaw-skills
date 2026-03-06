---
name: drive-search
description: Search Google Drive for files and folders
tags: [drive, files, search, documents, folders]
---
# Drive Search
## When to use
When finding files, folders, or documents in Google Drive.
## Execution
1. Parse: search query, optional --type (folder|document|spreadsheet), --max
2. Run: `gog drive list [--query "name contains 'x'"] [--type folder] [--max N]`
3. Return formatted file list with IDs and types
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log via log-event
