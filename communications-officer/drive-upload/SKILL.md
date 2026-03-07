---
name: drive-upload
description: Upload a file to Google Drive
tags: [drive, upload, file, share]
---
# Drive Upload
## When to use
When uploading files to Drive — reports, outputs, deliverables.
## Execution
1. Parse: local file path, optional --parent folder ID, --name
2. Run: `gog drive upload <local-path> --account relay.supernor@gmail.com [--parent <folder-id>] [--name "filename"]`
3. Return file ID and shareable link
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log upload via log-event with file details
