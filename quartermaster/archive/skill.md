---
name: archive
description: Archive a completed project channel — move to Archive category, pin final decision board, close open items. Usage: /archive
version: 1.0.0
author: relay
tags: [project, discord, archive, management]
---

# archive

## Invoke

```
/archive                # Archive the current project channel
/archive force          # Archive without confirmation prompt
```

## Steps

### 1. Confirmation (unless force)

```
⚠️ Archiving **#<channel-name>**. This will:
- Move channel to Archive category
- Pin the final decision board
- Mark all UNDECIDED items as DECIDED-NOT-DONE (reason: "project archived")

Type "yes" to confirm or "cancel" to abort.
```

### 2. Resolve open decisions

In `decisions/<channel-name>.md`, change all UNDECIDED entries to:
```
| <#> | <text> | DECIDED-NOT-DONE | Project archived without resolution | <today> |
```

SAVE-FOR-LATER items keep their status (they may be picked up in a future project).

### 3. Pin final decision board

Run the `/pin` skill to post and pin the final decision board.

Add a footer:
```
🗂️ **Project archived on <YYYY-MM-DD>.** This channel is now read-only.
```

### 4. Move channel to Archive category

Use Discord API to move the channel. Retrieve the `archives` category ID from `/home/node/.openclaw/shared-config.json`.
```
PATCH /channels/<channel_id>
{
  "parent_id": "<archive_category_id>"
}
```

### 5. Set channel read-only

Use Discord permission overrides to deny SEND_MESSAGES for @everyone in the archived channel.

### 6. Update project file

In `projects/<channel-name>.md`, set:
```markdown
**Status:** Archived (<YYYY-MM-DD>)
```

### 7. Confirm

```
🗂️ **#<channel-name>** archived.
- <N> decisions finalized
- <M> items were UNDECIDED → marked DECIDED-NOT-DONE
- <K> items SAVE-FOR-LATER (preserved)
- Channel moved to Archive — <YYYY-MM>
```

## Rules

- Never delete channels — always archive (history is valuable)
- Never change DONE or WONT-WORK statuses during archive
- SAVE-FOR-LATER items are preserved as-is
- If bot lacks Manage Channels, give Robert manual instructions
- Log the archive as a decision: `#<next> | Project archived | DONE | — | <date>`
