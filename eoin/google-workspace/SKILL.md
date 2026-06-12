---
name: google-workspace
description: Read, create, edit, and share Google Docs, Sheets, Drive files, Calendar events, and Gmail for eoin.s.crs@gmail.com. Live collaboration with Corinne (csupernor@gmail.com).
version: 2.0.0
author: eoin
tags: [google, drive, docs, sheets, calendar, gmail, workspace, collaboration, sharing]
---

# Google Workspace — Eoin's Google Account

## Purpose

Access Google Workspace as **eoin.s.crs@gmail.com** — Eoin's own Google identity.
Create, read, edit, and share documents for live collaboration with Corinne.

Corinne's personal account: **csupernor@gmail.com**
Eoin's Google account: **eoin.s.crs@gmail.com**

## When to use

- Corinne says "create a doc", "make a spreadsheet", "check the calendar"
- You need to store something in a shareable, editable format
- Corinne asks to collaborate on a document (live editing)
- You need to check Eoin's Gmail (sharing notifications, invitations)
- Corinne says "share this with me" or "send me the link"

## How to invoke

Use the `exec` tool:

```bash
exec workspace-cli.sh eoin "<gws command>"
```

**Command syntax (VERIFIED 2026-06-11 — the old `--query`/`--body` flags DO NOT EXIST):**
- URL/query/path parameters → `--params '<JSON>'` (fileId, q, fields, sendNotificationEmail live HERE)
- Request body → `--json '<JSON>'`
- File upload → `--upload <path>` + `--upload-content-type <mime>`. The path MUST be relative to the current directory (absolute paths are rejected). Write your file to the working dir first.

**Output parsing:** the first stdout line may be `Using keyring backend: file` — strip everything before the first `{` before parsing JSON. Errors come back as JSON `{"error":{...}}` plus a human line.

## ALWAYS DO THESE

1. **Always return a link** to any document you create or reference
2. **Always share with Corinne** (csupernor@gmail.com) when creating new docs
3. **Organize files** in clear, named folders — never dump files in root Drive
4. **Check for an existing folder before creating one** (a retry that re-creates makes duplicates — this happened on 2026-06-11)

## Verified Command Reference (each of these ran successfully 2026-06-11)

List files / search:
```bash
exec workspace-cli.sh eoin "drive files list"
exec workspace-cli.sh eoin "drive files list --params '{\"q\":\"name = \\\"Family Plans\\\" and trashed = false\"}'"
```

Create folder:
```bash
exec workspace-cli.sh eoin "drive files create --json '{\"name\":\"Family Plans\",\"mimeType\":\"application/vnd.google-apps.folder\"}'"
```

Create a Google Doc WITH content (markdown converts automatically — write the .md file first, in the current dir):
```bash
exec workspace-cli.sh eoin "drive files create --upload plan.md --upload-content-type text/markdown --json '{\"name\":\"Doc Title\",\"mimeType\":\"application/vnd.google-apps.document\",\"parents\":[\"FOLDER_ID\"]}'"
```

Share with Corinne (writer + notification email):
```bash
exec workspace-cli.sh eoin "drive permissions create --params '{\"fileId\":\"DOC_ID\",\"sendNotificationEmail\":true,\"emailMessage\":\"<warm one-liner>\"}' --json '{\"role\":\"writer\",\"type\":\"user\",\"emailAddress\":\"csupernor@gmail.com\"}'"
```

Verify a share actually happened (do this before telling Corinne it's shared):
```bash
exec workspace-cli.sh eoin "drive permissions list --params '{\"fileId\":\"DOC_ID\",\"fields\":\"permissions(emailAddress,role,type)\"}'"
```

Trash a file (e.g. an accidental duplicate):
```bash
exec workspace-cli.sh eoin "drive files update --params '{\"fileId\":\"FILE_ID\"}' --json '{\"trashed\":true}'"
```

## Links

Build from the ID — always give Corinne the link:
- Google Doc: `https://docs.google.com/document/d/DOC_ID/edit`
- Google Sheet: `https://docs.google.com/spreadsheets/d/DOC_ID/edit`
- Drive folder: `https://drive.google.com/drive/folders/FOLDER_ID`

## Other services (docs, sheets, gmail, calendar, slides...)

Same CLI, same `--params`/`--json` pattern, but the exact parameter names are NOT yet verified for these services. Before first use of a new command, run it with `--help` (e.g. `exec workspace-cli.sh eoin "gmail messages list --help"`) and follow what it says — do NOT guess flags. If a command fails twice, stop and escalate rather than retrying variations.

## Folder Organization Guide

```
eoin.s.crs@gmail.com Drive/
├── Family Plans/      (trips, money meetings, household)
├── Projects/          (CRS business, lead-gen)
├── Notes/             (session summaries, meeting notes)
├── Reports/           (briefs, digests)
└── Shared/            (docs Corinne shared that don't fit elsewhere)
```

## Error Diagnosis

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `ERROR: No credentials for account` | Credentials missing or path wrong | Check: `ls ~/.openclaw/gws-credentials/eoin/` |
| `invalid_grant` / `Token has been expired` | OAuth refresh token expired | Escalate to Robert — he re-auths via the Bridge health panel (per-account Google re-auth). Never send Corinne to Bridge internals. |
| `unexpected argument '--X' found` | Flag doesn't exist (old docs used fake flags) | Use `--params`/`--json`; run `--help` |
| `resolves to ... outside the current directory` | `--upload` with absolute path | Write the file to the current dir, use a relative path |
| `400 Required` | Missing required param (usually fileId) | fileId goes in `--params`, not `--json` |
| JSON parse fails on output | `Using keyring backend: file` banner line | Strip everything before the first `{` |
| `gws: command not found` | gws binary missing in this environment | Escalate to Robert (vendor install issue) — do NOT retry with sudo/other paths |

## Notes

- Eoin's Drive is separate from Corinne's Drive. Sharing creates a link in her "Shared with me", not a copy.
- Live editing: when both Corinne and Eoin have a doc open, edits appear in real-time.
- Calendar events are on eoin.s.crs@gmail.com's calendar. Invite Corinne's email to shared events.
- **Silo: never touch Relay's account or credentials.** Only ever `workspace-cli.sh eoin`.

## Related
- `chart search "google workspace"` — operational history
- OneNote skill — for Microsoft notebook access (different from Google)

Intent: Connected [I10] — Corinne collaborates with Eoin via shared documents
