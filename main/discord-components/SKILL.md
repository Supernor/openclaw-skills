---
name: discord-components
description: Send Discord messages with native buttons, select menus, modals, and polls using OpenClaw component format.
version: 1.0.0
author: reactor
tags: [discord, buttons, components, interactive, select, modal, poll]
---

# discord-components

Reference skill for sending interactive Discord messages. OpenClaw uses its OWN component format, NOT raw Discord API JSON.

## CLI Command

```bash
openclaw message send \
  --channel discord --account <account> --target <channel_id> \
  --components '<JSON>' \
  -m "optional fallback text"
```

The `--components` flag accepts a JSON object (NOT a raw Discord components array).

## Component Format

```json
{
  "reusable": true,
  "container": {"accentColor": 16711680},
  "text": "Optional top-level text",
  "blocks": [ ... ],
  "modal": { ... }
}
```

### Top-level fields:
- `reusable` (bool) - Keep buttons alive after session cleanup. USE THIS for cron-sent messages.
- `container.accentColor` (int) - Decimal color for the card border (red=16711680, yellow=16776960, green=5635840, blue=5814783)
- `text` (string) - Fallback text shown above blocks
- `blocks` (array) - Content blocks (see below)
- `modal` (object) - Form modal (see below)

## Block Types

### text
Simple text display. Supports markdown.
```json
{"type": "text", "text": "**Bold** and *italic* work here"}
```

### section
Text with optional accessory (thumbnail or button).
```json
{
  "type": "section",
  "text": "Main text here",
  "texts": ["Line 1", "Line 2", "Line 3"],
  "accessory": {
    "type": "button",
    "button": {"label": "Click me", "style": "primary"}
  }
}
```
- `text` OR `texts` (up to 3 items), not both required
- accessory: `{"type": "thumbnail", "url": "..."}` or `{"type": "button", "button": {...}}`

### separator
Visual divider between blocks.
```json
{"type": "separator", "divider": true, "spacing": "large"}
```
- `spacing`: "small", "large", 1, or 2
- `divider`: true/false (show line)

### actions
Buttons OR select menu (not both in same block).

**Buttons (up to 5 per row):**
```json
{
  "type": "actions",
  "buttons": [
    {"label": "Approve", "style": "success"},
    {"label": "Reject", "style": "danger"},
    {"label": "Details", "style": "primary"},
    {"label": "Skip", "style": "secondary"},
    {"label": "Docs", "style": "link", "url": "https://example.com"}
  ]
}
```

**Select menu (dropdown):**
```json
{
  "type": "actions",
  "select": {
    "type": "string",
    "placeholder": "Choose an action...",
    "minValues": 1,
    "maxValues": 1,
    "options": [
      {"label": "Option A", "value": "a", "description": "Description"},
      {"label": "Option B", "value": "b", "emoji": {"name": "fire"}}
    ]
  }
}
```

Select types: `string`, `user`, `role`, `mentionable`, `channel`

### media-gallery
Image gallery.
```json
{
  "type": "media-gallery",
  "items": [
    {"url": "https://...", "description": "Caption", "spoiler": false}
  ]
}
```

### file
Attach a file.
```json
{"type": "file", "file": "attachment://filename.txt", "spoiler": false}
```

## Button Spec

```json
{
  "label": "Button Text",
  "style": "primary",
  "url": null,
  "emoji": {"name": "fire", "id": null, "animated": false},
  "disabled": false,
  "allowedUsers": ["187662930794381312"]
}
```

Styles: `primary` (blurple), `secondary` (grey), `success` (green), `danger` (red), `link` (URL, requires `url` field)

`allowedUsers` restricts who can click. Accepts Discord user IDs.

## Modal (Form)

Attach a form modal that opens when a trigger button is clicked. Up to 5 fields.

```json
{
  "modal": {
    "title": "Report an Issue",
    "triggerLabel": "Open Form",
    "triggerStyle": "primary",
    "fields": [
      {
        "type": "text",
        "label": "Description",
        "placeholder": "What happened?",
        "required": true,
        "style": "paragraph"
      },
      {
        "type": "select",
        "label": "Severity",
        "options": [
          {"label": "Critical", "value": "critical"},
          {"label": "Warning", "value": "warning"},
          {"label": "Info", "value": "info"}
        ]
      },
      {
        "type": "radio",
        "label": "Action",
        "options": [
          {"label": "Fix now", "value": "fix"},
          {"label": "Investigate", "value": "investigate"},
          {"label": "Ignore", "value": "ignore"}
        ]
      }
    ]
  }
}
```

Field types: `text`, `checkbox`, `radio`, `select`, `role-select`, `user-select`
Text style: `"style": "paragraph"` for multiline

## Interaction Handling

Button/select clicks route back to the agent session that sent the message. The gateway:
1. Parses the custom_id (auto-generated, format: `occomp:cid=<id>`)
2. Looks up the stored entry (sessionKey, agentId, accountId)
3. Routes the interaction as a message to that agent session
4. Agent receives: "User clicked [Button Label]" or "User selected [Option]"

For CLI-sent messages, interactions route to the default agent for that channel.

Use `"reusable": true` to keep components active across session resets.
Use `"allowedUsers"` to restrict button access to specific Discord users.

## Known Discord Channel IDs

- #ops-alerts: 1477754571697688627
- #ops-dashboard: 1477754431780028598
- #ops-changelog: 1477754637527290030
- #ops-nightly: 1477754636046831738
- #daily-diary: 1480026250645868654
- Robert DM: 187662930794381312

## Examples

### Alert with fix buttons
```bash
openclaw message send --channel discord --account robert \
  --target 1477754571697688627 \
  --components '{"reusable":true,"container":{"accentColor":16711680},"blocks":[{"type":"text","text":"**CRITICAL** Codex OAuth failure (6x in 30 min)"},{"type":"separator","divider":true},{"type":"actions","buttons":[{"label":"Fix: codex-reauth","style":"success"},{"label":"Dismiss","style":"secondary"}]}]}'
```

### Status poll with select menu
```bash
openclaw message send --channel discord --account robert \
  --target 1477754571697688627 \
  --components '{"reusable":true,"blocks":[{"type":"text","text":"**System Check** — Which issue should we prioritize?"},{"type":"actions","select":{"type":"string","placeholder":"Pick one...","options":[{"label":"Codex Auth","value":"codex"},{"label":"Rate Limits","value":"rates"},{"label":"Agent Timeouts","value":"timeouts"}]}}]}'
```

### Form modal for incident reports
```bash
openclaw message send --channel discord --account robert \
  --target 1477754571697688627 \
  --components '{"reusable":true,"blocks":[{"type":"text","text":"**New incident detected** — please provide details"}],"modal":{"title":"Incident Report","triggerLabel":"Report Details","triggerStyle":"danger","fields":[{"type":"text","label":"What happened?","required":true,"style":"paragraph"},{"type":"select","label":"Severity","options":[{"label":"Critical","value":"critical"},{"label":"Warning","value":"warning"}]}]}}'
```

## Common Mistakes

1. DO NOT use raw Discord API format (type:1 ActionRow, type:2 Button). Use OpenClaw blocks format.
2. DO NOT put both buttons and select in the same actions block.
3. DO NOT exceed 5 buttons per actions block.
4. DO NOT forget `"reusable": true` for cron/CLI-sent messages (without it, buttons may expire).
5. DO NOT use backticks or special chars in component text if passing through bash — use single quotes around the JSON.

Intent: Observable [I13], Resourceful [I07]. Discovered: 2026-03-21.

## Polls

Separate CLI command — NOT part of `--components`.

```bash
openclaw message poll \
  --channel discord --account robert --target <channel_id> \
  --poll-question "Which issue to prioritize?" \
  --poll-option "Codex OAuth" \
  --poll-option "Rate Limits" \
  --poll-option "Agent Timeouts" \
  --poll-duration-hours 24 \
  --poll-multi
```

- `--poll-option` repeated 2-12 times (one per option)
- `--poll-duration-hours` sets expiry (Discord)
- `--poll-duration-seconds` for Telegram (5-600)
- `--poll-multi` allows multiple selections
- `--poll-anonymous` / `--poll-public` for Telegram
- `-m "text"` adds optional message body above the poll
- Works on both Discord and Telegram

### Poll example with message
```bash
openclaw message poll \
  --channel discord --account robert --target 1477754571697688627 \
  -m "Multiple issues detected by log-diagnostics. Vote on priority:" \
  --poll-question "Which to fix first?" \
  --poll-option "Codex OAuth refresh" \
  --poll-option "Gateway embedded timeouts" \
  --poll-option "Agent run errors" \
  --poll-duration-hours 4
```

Polls are native Discord polls — users vote directly, results visible in real time. No interaction handler needed.
