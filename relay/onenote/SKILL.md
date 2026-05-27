---
name: onenote
description: Read and write to the shared OneNote notebook (Relay Workspace). Browse pages, create notes, append content, search across all pages.
version: 1.0.0
author: relay
tags: [onenote, notebook, notes, microsoft, shared, workspace, writing]
---

# OneNote — Shared Notebook Access

## Purpose

Read and write to the "Relay Workspace" OneNote notebook shared between Robert and Relay.
Use this for persistent notes, meeting summaries, project briefs, or anything that should
live outside of chat and be editable by both Robert and the system.

Account: relay.supernor@outlook.com
Notebook: "Relay Workspace" → "Shared Notes" section

## When to use

- Robert says "save this to OneNote" or "put this in the notebook"
- You need to store something persistent that Robert should see on his phone/desktop
- Summarizing a session, decision, or plan for Robert to review later
- Robert asks "what's in the notebook" or "check OneNote"
- You want to leave Robert a note he'll see outside of Telegram

## How to invoke

Use the `exec` tool. The script is in the gateway's exec path:

```bash
exec onenote.sh <command> [args...]
```

**Do NOT** use `bash`, `sh`, or full paths. The exec tool resolves it automatically.

## Known IDs (saves round trips)

| Item | ID | Name |
|------|------|------|
| Notebook | `0-D8F8EB750405D121!s5a3e9586142e47a2b207e9acbc33519a` | Relay Workspace |
| Section | `0-D8F8EB750405D121!s8118449a183f4530914198e375ea61ba` | Shared Notes |

Use these directly — don't call `list-notebooks` or `list-sections` unless you need to discover new sections.

## Available commands

| Command | Args | Output | Use for |
|---------|------|--------|---------|
| `list-pages` | `<section-id>` | TSV: id, date, title | See what pages exist |
| `read-page` | `<page-id>` | Raw HTML | Read a page's content |
| `create-page` | `<section-id> <title> [html-body]` | Created page ID | New note/summary |
| `append-page` | `<page-id> <html-content>` | "OK" | Add to existing page |
| `search` | `<query>` | TSV: id, title | Find pages by content |
| `list-notebooks` | none | TSV: id, name | Discover notebooks (rarely needed) |
| `list-sections` | `<notebook-id>` | TSV: id, name | Discover sections (rarely needed) |

## Common workflows

### List recent pages
```bash
exec onenote.sh list-pages 0-D8F8EB750405D121!s8118449a183f4530914198e375ea61ba
```
Output is tab-separated: `page-id \t last-modified \t title`

### Read a page
```bash
exec onenote.sh read-page <page-id-from-list>
```
Output is HTML. Extract the text content — ignore HTML tags when summarizing for Robert.

### Create a new page
```bash
exec onenote.sh create-page 0-D8F8EB750405D121!s8118449a183f4530914198e375ea61ba "Page Title" "<p>Content goes here</p>"
```
- Title is required
- Body is optional (creates empty page if omitted)
- Content must be valid HTML — wrap text in `<p>` tags
- Use `<h1>`, `<h2>`, `<ul><li>` for structure
- **Do NOT use markdown** — OneNote expects HTML

### Append to an existing page
```bash
exec onenote.sh append-page <page-id> "<p>New content appended at the bottom</p>"
```
- Appends to the END of the page body
- Returns "OK" on success, empty on failure
- Use this for running logs or incremental notes

### Search across all pages
```bash
exec onenote.sh search "keyword"
```
Output is tab-separated: `page-id \t title`

## Formatting guide for OneNote HTML

```html
<!-- Heading -->
<h1>Main Title</h1>
<h2>Subsection</h2>

<!-- Paragraphs -->
<p>Regular text paragraph.</p>

<!-- Bullet list -->
<ul>
  <li>First item</li>
  <li>Second item</li>
</ul>

<!-- Bold/italic -->
<p><b>Bold text</b> and <i>italic text</i></p>

<!-- Table -->
<table>
  <tr><td>Cell 1</td><td>Cell 2</td></tr>
  <tr><td>Cell 3</td><td>Cell 4</td></tr>
</table>

<!-- Timestamp (useful for logs) -->
<p><i>Updated: 2026-05-26T19:00:00Z</i></p>
```

**Do NOT use**: markdown syntax, backticks, `\n` newlines in HTML strings, unescaped quotes in content.

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `No OneNote access token found` | Token expired or missing | Run on host: `python3 /root/.openclaw/scripts/onenote-auth.py` (needs Robert's browser for device code flow) |
| `401 Unauthorized` | Access token expired (refresh failed) | Check cron: `crontab -l \| grep onenote`. Token refreshes every 30 min via `onenote-refresh-token.sh`. If refresh token expired (~6 months), re-auth needed. |
| `403 Forbidden` | Missing write scope | Re-auth with expanded scopes. Current scopes: Notes.ReadWrite, Notes.Create, Files.ReadWrite.All |
| Empty output from `list-pages` | Section ID wrong or no pages | Verify section ID: `exec onenote.sh list-sections 0-D8F8EB750405D121!s5a3e9586142e47a2b207e9acbc33519a` |
| `create-page` returns error JSON | HTML body has unescaped characters | Escape quotes in HTML content. Avoid shell special characters in the body argument. |

## Notes

- Robert can see and edit these pages on his phone (OneNote app) or desktop
- Content syncs in near-real-time — what you write appears within seconds
- The notebook is on relay.supernor@outlook.com, shared with Robert's Microsoft account
- Token auto-refreshes every 30 min via cron — should rarely expire
- If token does expire, it needs Robert's browser (device code flow) — tell him and offer to help

## Related
- `chart search "onenote"` — operational history
- Google Workspace tools (MCP) — for Docs/Sheets/Drive (different from OneNote)
- `exec onenote-refresh-token.sh` — manual token refresh

Intent: Connected [I10] — Robert has access to system notes from his phone
