---
name: project-audit
description: Compare the decision board against recent chat history to find stale, missing, or contradicted decisions. Also audits workspace token efficiency. Usage: /project-audit
version: 2.0.0
author: relay
tags: [decisions, project, audit, reconciliation, signal-architect, context-hygiene]
---

# project-audit

## Invoke

```
/project-audit                  # Audit against recent chat (default: last 50 messages)
/project-audit deep             # Audit against last 200 messages
/project-audit signal           # Perform deep audit with Signal Architect standards
/project-audit context          # Token efficiency audit across all agent workspaces
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

### 3. Signal Architect Standards Check

When performing a Signal audit or processing results, verify the following:

#### A. RACP Check (Recipient-Aware Context Protocol)
Verify agents are correctly using markers in their communications/logs:
- 👤 (Human Interaction/User-facing)
- ⚙️ (System/Internal Processing) — with optional `:agent-id` targeting
- 📡 (Signal/External Communication / Shared)
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

---

## Context Audit Mode (`/project-audit context`)

Measures token efficiency across all agent workspaces and flags audience mismatches.

### Steps

#### 1. Measure all workspace files

For each agent workspace (`workspace/`, `workspace-relay/`, `workspace-spec-github/`, `workspace-spec-projects/`):
- List all `.md` files (excluding `.git/`)
- For each file: count characters, estimate tokens (chars / 4)
- Sum total per agent

#### 2. Agent role definitions

| Agent | ID | Should receive |
|-------|-----|---------------|
| Relay | relay | Human-facing: user prefs, Discord reading, button interpretation, ops channel awareness |
| Captain | main | Routing only: agent roster, keyword→agent mappings, handoff format |
| Repo-Man | spec-github | Infrastructure: scripts, Discord posting/management, webhooks, channel admin, model health |
| Quartermaster | spec-projects | Projects: decisions, polls for voting, archival |

#### 3. Flag mismatches

For each file in each workspace, check if the content matches that agent's role:

| Flag | Meaning |
|------|---------|
| 🎯 Targeted | Content matches agent role — good |
| ⚠️ Broad | Content is generic/shared but could be trimmed for this agent |
| 🚫 Misplaced | Content doesn't serve this agent at all — wasted tokens |
| 📋 Duplicate | Same content exists in multiple workspaces verbatim |

#### 4. Check for RACP source files

If a file exists in multiple workspaces, check if a RACP-marked source exists at `~/.openclaw/docs/`. If yes, verify the workspace copies were generated by `racp-split.sh` (should be targeted, not identical).

#### 5. Report

```
📊 **Context Audit — Token Efficiency**

| Agent | Files | Est. Tokens | Issues |
|-------|-------|-------------|--------|
| Captain | 3 | 5,054 | 1 Broad |
| Relay | 12 | 12,004 | 2 Broad, 1 Misplaced |
| Repo-Man | 21 | 13,846 | 0 |
| Quartermaster | 11 | 4,327 | 1 Misplaced |

**Flags:**
🚫 **Misplaced:** `DISCORD-PLAYBOOK.md` in Quartermaster (2,289 tokens) — QM only needs polls section (~200 tokens)
⚠️ **Broad:** `CHANGELOG.md` in Relay (1,804 tokens) — Relay never needs full change history
📋 **Duplicate:** `CHANGELOG.md` identical in Captain + Relay

**Recommendations:**
1. Split DISCORD-PLAYBOOK.md using racp-split.sh — saves ~5,500 tokens/turn
2. Move CHANGELOG.md out of workspaces — reference doc, not per-turn context
3. Move RECOVERY_PLAN to docs/ — one-time document, ~4,746 tokens/turn saved

**Total potential savings: ~12,000 tokens/turn**
```

#### 6. Scheduling

Context audit should run monthly (add to Quartermaster's audit schedule) or on-demand after any workspace restructuring.

---

## Rules

- Never auto-modify the decision board — only report discrepancies
- Never auto-modify workspace files in context audit — only recommend changes
- Be conservative with "Stale" flags — casual mentions don't count, only clear reversals or contradictions
- "Missing" should only flag things that sound like actual decisions, not brainstorming or hypotheticals
- Include approximate message timestamps or context so the user can find the relevant discussion
- **Signal Priority:** RACP and Security risks should be listed at the top of the report.
- **Context audit:** Report token counts, not character counts — tokens are the currency that matters
