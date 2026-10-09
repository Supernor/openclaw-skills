---
name: bridge-edit-verify
description: Edit a Bridge section, take a screenshot, verify the result visually. Self-improving — logs what worked and what didn't.
tags: [bridge, design, visual, self-improving]
version: 1.0.0
---

# bridge-edit-verify — Edit, Screenshot, Verify

## When to use
Any Bridge CSS or layout edit. Every time. No exceptions.

## The Loop

### 1. BEFORE editing
- Save a snapshot: `POST /api/bridge/save-current` with a name
- Take a "before" screenshot:
  ```
  ops_insert_task: {
    agent: "spec-design",
    task: "screenshot before edit",
    meta: { host_op: "screenshot", url: "http://localhost:8083/", width: 360, height: 800, output_path: "/tmp/bridge-before.png" }
  }
  ```
- Read the module files for the section you're editing:
  `modules/{section}/styles.css` and `modules/{section}/section.html`
- Read the alignment guidelines at the top of index.html

### 2. EDIT
- CSS-only changes: use `host_op: bridge-style` (rejects non-CSS edits)
- Feature changes: use `host_op: bridge-edit`
- Edit ONLY the module's styles.css file, not the monolithic style.css
- Stay within the section's CSS namespace (.board-*, .workshop-*, etc.)

### 3. AFTER editing
- Take an "after" screenshot (same dimensions)
- Compare before/after — did the change improve the section?
- Verify: do all DOM IDs still exist? `grep "id=" index.html` should match expectations

### 4. EVALUATE
Ask yourself:
- Does this look right at 360px wide (Samsung)?
- Does the text have enough contrast?
- Do interactive elements have 44px minimum touch targets?
- Does the layout use flexbox (not float/absolute)?
- Is anything overflowing or clipped?

If any answer is NO → revert via `/api/bridge/rollback` and try again.

### 5. LOG THE RESULT
Chart what you learned:
```
chart_add "lesson-bridge-{date}" "Edited {section}: {what}. Result: {good/bad}. Learned: {insight}." reading 0.6
```

Good results: chart what worked so you do it again.
Bad results: chart what failed so you don't repeat it.

## Screenshot API
```
host_op: screenshot
meta: {
  url: "http://localhost:8083/",
  width: 360,    // Samsung mobile
  height: 800,
  output_path: "/tmp/bridge-screenshot.png"
}
```
Widths to test: 360 (phone), 768 (tablet), 960 (desktop split)

## Self-Improvement
After 5 logged edits, read your own lessons:
```
chart_search "lesson-bridge"
```
Patterns will emerge — what CSS changes work, what breaks, what Robert likes.

## Key Files
- `modules/{section}/styles.css` — the CSS to edit
- `modules/{section}/section.html` — the HTML structure (read-only for style edits)
- `index.html` top comment block — design alignment guidelines
- `docs/flexbox-use-cases-reference.md` — flexbox patterns
- `docs/policy-style-separation.md` — CSS-only vs feature edits
