---
name: import-context
description: Structured context import for Robert. Accepts structured input (MD files, notes, decisions) and stores in fleet memory. Robert's equivalent of Eoin's import-conversations skill.
version: 1.0.0
author: relay
tags: [import, context, knowledge, memory, notes, decisions, structured]
---

# import-context — Structured Context Import

## Purpose

Robert's version of Corinne's `import-conversations` skill. Same capability, but expects structured input — Robert doesn't need hand-holding.

## When to Trigger

- Robert says "import this", "add this to memory", "here's context", "store this"
- Robert sends a file or pasted content with the intent to store it
- Robert shares a Google Doc link with fleet-relevant content

## Input Formats

### 1. Pasted Text / Notes
Robert pastes directly. Parse, categorize, store.

### 2. Markdown Files
Accept .md files. Parse structure, extract key decisions and knowledge.

### 3. Google Docs Link
Fetch via gog if available, or note for later processing.

### 4. Structured Commands
Robert may prefix with intent:
- "Decision: [topic]" → chart as `decision-[topic]`
- "Policy: [rule]" → chart as `governance-[topic]`
- "For Corinne: [context]" → route to Eoin's memory via Captain

## Processing

### Step 1: Accept
"Got it. Processing."

### Step 2: Categorize
Identify what type of content:
- Decision → chart as `decision-*`, importance 0.9
- Knowledge → chart as `reading-*`, importance 0.7
- Policy → chart as `governance-*`, importance 0.85
- Context for agents → route to appropriate workspace memory
- Cross-user context → store in shared workspace and notify relevant agent

### Step 3: Confirm
Brief confirmation with what was stored and where:
> Stored: [count] items. [Brief list]. Chartroom + [affected workspaces].

## Rules

- Robert is Stage 2-3 — minimal output, confirm and done
- If content affects Corinne's domain, route through Captain to Eoin
- Chart everything — nothing imported should be lost
- Don't ask for clarification on obvious categorization — infer and confirm
