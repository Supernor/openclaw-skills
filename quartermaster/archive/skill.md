---
name: archive
description: Archive a completed project channel — move to Archive category, pin final decision board, close open items, suspend session. Usage: invoked via /plan menu
version: 2.0.0
author: relay
tags: [project, discord, archive, management]
---

# archive

Invoked by Relay's /plan menu, not directly by the user.

## Invoke

Called internally when Robert selects "Archive" from the /plan project menu.

## Steps

### 1. Resolve open decisions

In `decisions/<channel-name>.md`, change all UNDECIDED entries to:
```
| <#> | <text> | DECIDED-NOT-DONE | Project archived without resolution | <today> |
```

SAVE-FOR-LATER items keep their status (they may be picked up in a future project).

### 2. Pin final decision board

Run the pin-decisions skill to post and pin the final decision board.

Add a footer:
```
Project archived on <YYYY-MM-DD>. Type /plan to reactivate.
```

### 3. Move channel to Archive category

Use `channel-edit` to set `parentId` to the archives category ID from `/home/node/.openclaw/shared-config.json`.

### 4. Set channel read-only

Use `channel-permissions` to deny SEND_MESSAGES for @everyone in the archived channel.

### 5. Close session (DO NOT DELETE)

Close the OpenClaw session for this channel. The session data must be preserved for potential reactivation. Closing means the session stops accepting new messages and won't consume tokens, but the history and context remain on disk.

If the session API supports a close/suspend action, use that. If not, leave the session as-is — the read-only channel permission prevents new messages from arriving anyway.

### 6. Update project file

In `projects/<channel-name>.md`, set:
```markdown
**Status:** Archived (<YYYY-MM-DD>)
```

### 7. Return result

```
RESULT: Project #<channel-name> archived
STATUS: success
DETAILS: <N> decisions finalized, <M> UNDECIDED marked DECIDED-NOT-DONE, <K> SAVE-FOR-LATER preserved, session closed (data kept)
```

## Rules

- Never delete channels — always archive
- Never delete sessions — always close/suspend
- Never change DONE or WONT-WORK statuses during archive
- SAVE-FOR-LATER items are preserved as-is
- If bot lacks Manage Channels, give Robert manual instructions via Relay
- Log the archive as a decision: `#<next> | Project archived | DONE | <date>`
