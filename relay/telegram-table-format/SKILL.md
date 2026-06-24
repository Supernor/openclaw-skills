---
name: telegram-table-format
description: Render tables/columnar data as Telegram-native nested bullets instead of pipe/markdown tables, which wrap badly on mobile.
version: 1.0.0
tags: [telegram, formatting, tables, mobile, ux]
---

# Telegram Table Format

## Purpose
Teach an agent how to present tabular or columnar data in Telegram in a way
that actually reads well on a phone. Telegram does NOT render real tables.
Pipe-style markdown tables (`| Col | Col |`) and monospace code-block tables
both wrap badly on mobile screens, lose alignment, and are painful to read.
This skill replaces them with a Telegram-native format.

## When to use
- You are about to send a message to the user via Telegram that contains a
  table, grid, comparison, metrics list, or any columnar data.
- The user asks you to "show me a table" of something.
- You are summarizing structured data (stats, scores, comparisons, schedules).

## Core principle
**Never emit a raw pipe table to Telegram.** Instead, use nested bullets with
indentation and familiar bullet symbols to show hierarchy. This is the same
visual structure Word and OneNote use — top-level items with sub-details
indented beneath them. It reads cleanly on any screen size.

Bullet symbol convention:
- Top level (row label / header): `•`
- Second level (field name + value): `◦` (indented under its parent)
- Third level (sub-detail): `▪` (indented further)

## The format (decision algorithm)

Read the data, then pick ONE of these paths:

**Path 1 — Bullet-detail format (PREFERRED)**
Use when: columns ≤ 5 AND rows ≤ ~10.
Each row becomes a header bullet. Its column values become indented
sub-bullets beneath it. This is the default choice for almost all cases.

**Path 2 — Inline monospace**
Use when: each row fits on one short line (≤ ~80 chars total) AND there are
only 2 columns (a label and a value). Wrap short values in single backticks.
Use sparingly — only when the label+value pair is genuinely compact.

**Path 3 — Rendered image**
Use when: the table is dense or wide (many columns, many rows) AND an image
rendering tool is available. Offer this to the user before sending.

**Fallback — Plain text with clear line breaks**
When none of the above fits: plain prose with clear separators. Never
fall back to a pipe table.

## Examples

### BEFORE — ugly pipe table (do not send this)
```
| Metric   | Value  |
|----------|--------|
| Latency  | 350ms  |
| Errors   | 0.2%   |
| Uptime   | 99.9%  |
```
This wraps on mobile and loses its columns entirely.

---

### AFTER — bullet-detail format (2-column example)

**System Health**

• Latency
  ◦ 350ms
• Errors
  ◦ 0.2%
• Uptime
  ◦ 99.9%

---

### AFTER — bullet-detail format (3–4 column example)

Imagine a table: Engine | Accuracy | Best At | Worst At

**Engine Performance**

• Codex
  ◦ Accuracy: 10.0
  ◦ Best at: scripting
  ◦ Worst at: auditing
• Gemini
  ◦ Accuracy: 8.2
  ◦ Best at: auditing
  ◦ Worst at: sandbox validation
• Claude
  ◦ Accuracy: 7.6
  ◦ Best at: auditing
  ◦ Worst at: no scripting data yet

---

### Inline monospace (2-column, short values only)
`Latency` → `350ms`
`Errors`  → `0.2%`
`Uptime`  → `99.9%`

Use this ONLY when the label+value pairs are short enough to stay on one line.

## Learning the user's preference

If the user states a format preference — for example "I prefer inline
monospace" or "use the bullet format going forward" — record it in the
agent's preference memory file and apply it in all future messages without
being asked again.

- Relay (Robert's agent): append to `memory/robert-prefs.md`
- Eoin (Corinne's agent): append to `memory/corinne-prefs.md`

Write a line like:
`Table format preference: bullet-detail (stated YYYY-MM-DD)`

Do NOT create any external feedback files, JSON stores, or runtime state.
Preference memory is the only mechanism. If no preference has been recorded,
default to bullet-detail format (Path 1).
