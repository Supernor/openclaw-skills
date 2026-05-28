---
name: google-workspace
description: Read, create, edit, and share Google Docs, Sheets, Drive files, Calendar events, and Gmail for eoin.s.crs@gmail.com. Live collaboration with Corinne (csupernor@gmail.com).
version: 1.0.0
author: eoin
tags: [google, drive, docs, sheets, calendar, gmail, workspace, collaboration, sharing]
---

# Google Workspace — Relay's Google Account

## Purpose

Access Google Workspace as **eoin.s.crs@gmail.com** — Relay's own Google identity.
Create, read, edit, and share documents for live collaboration with Corinne.

Corinne's personal account: **csupernor@gmail.com**
Relay's Google account: **eoin.s.crs@gmail.com**

## When to use

- Corinne says "create a doc", "make a spreadsheet", "check my calendar"
- You need to store something in a shareable, editable format
- Corinne asks to collaborate on a document (live editing)
- You need to check Relay's Gmail (sharing notifications, invitations)
- Corinne says "share this with me" or "send me the link"

## How to invoke

Use the `exec` tool. The script is in the gateway's exec path:

```bash
exec workspace-cli.sh eoin "<gws command>"
```

**Do NOT** use `bash`, `sh`, or full paths. The exec tool resolves it automatically.

## ALWAYS DO THESE

1. **Always return a link** to any document you create or reference
2. **Always share with Corinne** (csupernor@gmail.com) when creating new docs
3. **Organize files** in clear, named folders — be a "neat freak"
   - Root folders: `Projects/`, `Notes/`, `Reports/`, `Shared/`
   - Sub-folders by topic: `Projects/Relay Primary Interface/`, `Notes/Session Summaries/`
   - Never dump files in root Drive — always in a folder

## Quick Reference

| Task | Command |
|------|---------|
| List files | `exec workspace-cli.sh eoin "drive files list"` |
| Search files | `exec workspace-cli.sh eoin "drive files list --query 'name contains \"report\"'"` |
| List folder | `exec workspace-cli.sh eoin "drive files list --query '\"FOLDER_ID\" in parents'"` |
| Create folder | `exec workspace-cli.sh eoin "drive files create --name 'Folder Name' --mime-type application/vnd.google-apps.folder"` |
| Create Doc | `exec workspace-cli.sh eoin "drive files create --name 'Doc Title' --mime-type application/vnd.google-apps.document"` |
| Create Sheet | `exec workspace-cli.sh eoin "drive files create --name 'Sheet Title' --mime-type application/vnd.google-apps.spreadsheet"` |
| Read Doc | `exec workspace-cli.sh eoin "docs documents get --document-id 'DOC_ID'"` |
| Read Sheet | `exec workspace-cli.sh eoin "sheets spreadsheets values get --spreadsheet-id 'SHEET_ID' --range 'Sheet1'"` |
| List Calendar | `exec workspace-cli.sh eoin "calendar events list --calendar-id primary --single-events true --order-by startTime"` |
| Check Gmail | `exec workspace-cli.sh eoin "gmail messages list --user-id me --q 'is:unread' --max-results 5"` |
| Read Email | `exec workspace-cli.sh eoin "gmail messages get --user-id me --id 'MSG_ID'"` |

## Creating Documents — Full Workflow

### Step 1: Ensure folder exists
```bash
exec workspace-cli.sh eoin "drive files list --query 'name = \"Projects\" and mimeType = \"application/vnd.google-apps.folder\"'"
```
- **If found:** use the folder ID from output
- **If empty:** create it:
```bash
exec workspace-cli.sh eoin "drive files create --name 'Projects' --mime-type application/vnd.google-apps.folder"
```

### Step 2: Create the document in the folder
```bash
exec workspace-cli.sh eoin "drive files create --name 'Document Title' --mime-type application/vnd.google-apps.document --parents 'FOLDER_ID'"
```
Output is JSON with `id` field — that's the document ID.

### Step 3: Share with Corinne
```bash
exec workspace-cli.sh eoin "drive permissions create --file-id 'DOC_ID' --body '{\"role\":\"writer\",\"type\":\"user\",\"emailAddress\":\"csupernor@gmail.com\"}' --send-notification-email true"
```

### Step 4: Return the link
Build the link from the document ID:
- Google Doc: `https://docs.google.com/document/d/DOC_ID/edit`
- Google Sheet: `https://docs.google.com/spreadsheets/d/DOC_ID/edit`
- Drive file: `https://drive.google.com/file/d/DOC_ID/view`
- Drive folder: `https://drive.google.com/drive/folders/FOLDER_ID`

**Always give Corinne the link.** Every time. Whether the doc was just created or already existed.

## Reading Gmail

When Corinne or someone shares a document, Relay gets a notification email.

### Check for new emails
```bash
exec workspace-cli.sh eoin "gmail messages list --user-id me --q 'is:unread' --max-results 5"
```
Output is JSON with `messages` array. Each has an `id`.

### Read a specific email
```bash
exec workspace-cli.sh eoin "gmail messages get --user-id me --id 'MESSAGE_ID' --format metadata --metadata-headers 'From,Subject,Date'"
```
- **If it's a sharing notification:** tell Corinne what was shared and ask what to do
- **If it's an invitation:** tell Corinne and ask if you should accept

## Output Format

The gws CLI returns JSON. Parse it to extract IDs, names, and links. Common patterns:

**File list:** `{ "files": [{ "id": "...", "name": "...", "mimeType": "...", "modifiedTime": "..." }] }`
**File create:** `{ "id": "...", "name": "...", "mimeType": "..." }`
**Calendar events:** `{ "items": [{ "summary": "...", "start": {...}, "htmlLink": "..." }] }`
**Gmail messages:** `{ "messages": [{ "id": "...", "threadId": "..." }] }`

## Folder Organization Guide

```
eoin.s.crs@gmail.com Drive/
├── Projects/
│   ├── Relay Primary Interface/
│   ├── Workshop Ideas/
│   └── Business Plans/
├── Notes/
│   ├── Session Summaries/
│   └── Meeting Notes/
├── Reports/
│   ├── Weekly Digests/
│   └── System Reports/
└── Shared/
    └── (docs shared by Corinne that don't fit elsewhere)
```

Create folders as needed. Always put documents in the most specific folder.

## Error Diagnosis

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `ERROR: No credentials for account` | Credentials missing or path wrong | Check: `ls ~/.openclaw/gws-credentials/eoin/` |
| `invalid_grant` or `Token has been expired` | OAuth refresh token expired (~6 months) | Corinne must re-auth on Bridge: Settings > Re-auth > gws-eoin |
| `403 Forbidden` | Missing scope for this API | Re-auth with expanded scopes |
| `404 Not Found` on file operations | Wrong file/doc ID | List files first, copy the ID from output |
| Empty `files` array | No files match query, or Drive is empty | Try without query filter |
| `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` error | gws CLI misconfigured | Check workspace-cli.sh has correct path |

## Notes

- Relay's Drive is separate from Corinne's Drive. Sharing creates a link, not a copy.
- Live editing: when both Corinne and Relay have a doc open, edits appear in real-time.
- Calendar events are on eoin.s.crs@gmail.com's calendar. Invite Corinne's email to shared events.
- Gmail is eoin.s.crs@gmail.com's inbox. Use it to check for sharing notifications.
- Token auto-refreshes via gws CLI. If it expires (~6 months), Bridge has the reauth flow.

## Related
- `chart search "google workspace"` — operational history
- `chart read ref-mcp-server-openclaw-gateway` — MCP server with GWS tools (for Claude Code)
- OneNote skill — for Microsoft notebook access (different from Google)
- `exec onenote.sh` — OneNote commands

Intent: Connected [I10] — Corinne collaborates with Relay via shared documents
