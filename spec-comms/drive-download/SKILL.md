---
name: drive-download
description: Download or export a file from Google Drive
tags: [drive, download, export, file]
---
# Drive Download
## When to use
When retrieving files from Drive for processing or delivery.
## Execution
1. Parse: file ID, optional --output path, --format (pdf|docx|txt)
2. Run: `gog drive download <file-id> --account relay.supernor@gmail.com [--output <path>] [--format pdf]`
3. Confirm download path and file size
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log download via log-event

Intent: Resourceful [I07]. Purpose: [P-TBD].
