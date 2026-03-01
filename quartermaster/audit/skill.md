---
name: audit
description: Compare the decision board against recent chat history to find stale, missing, or contradicted decisions. Usage: /audit
version: 1.1.0
author: relay
tags: [decisions, project, audit, reconciliation, signal-architect]
---

# audit

## Invoke

```
/audit                  # Audit against recent chat (default: last 50 messages)
/audit deep             # Audit against last 200 messages
/audit signal           # Perform deep audit with Signal Architect standards
```

## Steps

### 1. Load decision board

Read `decisions/<channel-name>.md`. If none exists: "No decisions to audit — use `/decide` to start tracking."

### 2. Read chat history and attachments

Use the channel's recent message history (50 messages default, 200 for deep).

**IMPORTANT — Read all file attachments in this channel:**
- Scan this channel's message history for any messages with file attachments (`.md`, `.txt`, `.json`, or other text files)
- For each attachment, use the `web_fetch` tool to download and read the file content from the Discord CDN URL
- These uploaded files often contain project plans, checklists, task lists, or context documents with decisions already made
- Treat the full contents of every uploaded file as part of the audit context — equal weight to chat messages
- Only files uploaded to THIS channel — never pull from other channels
- **Do not skip this step.** If attachments exist and you cannot read them, report that in the audit output.

### 3. Signal Architect Standards Check (New)

When performing a Signal audit or processing results, verify the following:

#### A. RACP Check (Role-Action-Context-Payload)
Verify agents are correctly using markers in their communications/logs:
- 👤 (Human Interaction/User-facing)
- ⚙️ (System/Internal Processing)
- 📡 (Signal/External Communication)
Flag any inconsistencies or missing markers in automated logs or decision records.

#### B. Shadow Context Security
Audit `LIMITS.md` (or relevant security configuration files) for:
- Encryption status of stored context.
- Backup frequency and integrity checks.
- If `LIMITS.md` is missing or lacks these details, flag as a high-security risk.

#### C. Ratio-Based Seasoning
Verify that any new skills or automated workflows being discussed/implemented maintain a **>85% success rate** threshold.
- If chat reveals repeated failures for a specific tool or skill, flag it as "Unseasoned" or "High-Risk."

#### D. Conflict Risk
Check for file-locking or concurrency logic in discussions involving parallel tasks.
- Ensure that multiple agents or sub-agents aren't attempting to write to the same file (e.g., `decisions/*.md`) without a defined locking mechanism.

### 4. Cross-reference

For each logged decision, check if recent chat OR uploaded documents contradict, supersede, or revisit it. Also scan chat AND attachments for decisions that were never logged.

When an uploaded document contains a checklist or task list with completed/incomplete items, flag:
- Completed items not in the decision board → ⚠️ Missing (mark as DONE candidates)
- Incomplete items not in the decision board → ⚠️ Missing (mark as UNDECIDED candidates)
- Items marked done in the doc but not in the decision board → ⚠️ Missing

Report categories:

| Flag | Meaning |
|------|---------|
| ⚠️ Missing | Decision discussed in chat but not logged |
| ⚠️ Stale | Logged decision contradicted by later discussion |
| ⚠️ Revisited | A WONT-WORK or DECIDED-NOT-DONE item was reopened in chat |
| ⚠️ Signal-Risk | Failed RACP, Ratio, Security, or Conflict check |
| ✅ Consistent | Logged decision still matches chat context |

### 5. Post audit report

```
🔍 **Decision Audit — #<channel-name>**
<N> messages reviewed

⚠️ **Signal-Risk:** RACP Check failed — 📡 markers missing from external signal logs.
⚠️ **Signal-Risk:** Shadow Context — `LIMITS.md` encryption status UNVERIFIED.
⚠️ **Signal-Risk:** Ratio Check — `weather` skill at 72% success (threshold >85%).
⚠️ **Missing:** "Switch from WebSocket to SSE" — discussed around <time>, not logged
⚠️ **Stale:** Decision #3 "Use ElevenLabs for TTS" marked DONE but later discussion suggests shelving
✅ Decision #1 — consistent

Run `/decide <status> <text>` to update flagged items.
```

### 6. If clean

```
✅ **Decision Audit — #<channel-name>** — All <N> decisions consistent with recent chat and Signal Architect standards.
```

## Rules

- Never auto-modify the decision board — only report discrepancies
- Be conservative with "Stale" flags — casual mentions don't count, only clear reversals or contradictions
- "Missing" should only flag things that sound like actual decisions, not brainstorming or hypotheticals
- Include approximate message timestamps or context so the user can find the relevant discussion
- **Signal Priority:** RACP and Security risks should be listed at the top of the report.
