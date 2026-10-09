---
name: audit-skill
description: Audit existing skills against create-skill best practices. Finds gaps, scores quality, and produces upgrade recommendations.
version: 1.0.0
tags: [meta, quality, audit, skills]
---

# Audit Skill

## Purpose
Check whether existing skills follow the best practices defined in
`/create-skill`. Produces a quality score and specific upgrade recommendations
for each skill audited. Use this to maintain skill quality over time and
catch drift before it becomes invisible.

## When to use
- After a batch of skills are created or upgraded (quality gate)
- Periodically (monthly) to catch skills that have drifted
- When Robert asks about skill quality
- Before trusting an agent to run autonomously with a skill

## How it works

This skill does NOT duplicate the best practices — it reads them from
`/create-skill` (the single source of truth) and checks each skill against
them. If best practices are updated in create-skill, this audit automatically
checks against the new standard.

## Steps

### Phase 1: Load the checklist

Read `/root/.openclaw/skills/create-skill/SKILL.md` and extract the best
practices. As of v1.0.0, the checklist is:

| # | Practice | What to check |
|---|----------|--------------|
| 1 | Error messages teach the agent | Does the skill have ERROR MEANING / HISTORY / FIX patterns? |
| 2 | Scripts do work, skills interpret | Does the skill invoke a script, or contain inline bash logic >5 lines? |
| 3 | Includes the "why" | Do comments explain WHY, not just WHAT? |
| 4 | References charts | Does it have `chart read` or `chart search` references? |
| 5 | Shows what success looks like | Does it describe expected output format? |
| 6 | Coordinator pattern (if multi-step) | Does a multi-step workflow use a coordinator skill? |
| 7 | Post-update section | Does it mention what to check after OpenClaw updates? |
| 8 | Versioned | Does frontmatter have a version field? |

Additional structural checks:
| # | Check | What to look for |
|---|-------|-----------------|
| 9 | Has Purpose section | 2-3 sentences explaining what and why |
| 10 | Has "When to use" | Specific triggers, not vague |
| 11 | Has Error diagnosis | Table or structured error handling |
| 12 | Has Related section | Links to other skills and charts |
| 13 | Has Intent line | Maps to system intents |
| 14 | Frontmatter complete | name, description, version, author, tags |

### Phase 2: Audit target skills

For each skill to audit:

```bash
# List all skills in a workspace
ls /root/.openclaw/workspace-<agent>/skills/
```

Read each SKILL.md and score it against the checklist:

**Scoring:**
- Each practice check: 1 point if present, 0 if missing
- Total possible: 14 points
- Grade: 12-14 = A (production ready), 9-11 = B (functional, needs polish),
  6-8 = C (works but fragile), <6 = D (needs rewrite)

### Phase 3: Produce report

Format the results:

```
Skill Audit Report — <agent> (<date>)

SUMMARY: <N> skills audited, average score <X>/14 (Grade <Y>)

| Skill | Version | Score | Grade | Missing |
|-------|---------|-------|-------|---------|
| backup-suite | 1.0.0 | 13/14 | A | post-update section |
| config-tag | 1.0.0 | 5/14 | D | errors, charts, why, success, related |
| ... | ... | ... | ... | ... |

TOP RECOMMENDATIONS:
1. <skill-name>: Add error diagnosis table (currently no failure handling)
2. <skill-name>: Add chart references (agent has no operational context)
3. <skill-name>: Bump version and add "When to use" triggers
```

### Phase 4: Upgrade or flag

For each skill scoring below B:
- If you have enough context to upgrade it: do so, following `/create-skill`
- If the skill is complex or you're unsure: flag it for a dedicated upgrade session
- After upgrading: re-audit to verify the score improved

## Auditing skills across ALL agents

To audit system-wide:
```bash
# Find all SKILL.md files
find /root/.openclaw/workspace*/skills/ -name "SKILL.md" | wc -l

# Audit one workspace at a time
for ws in /root/.openclaw/workspace*/skills/; do
  echo "=== $(basename $(dirname $ws)) ==="
  ls "$ws"
done
```

Priority order for auditing:
1. Repo-Man (spec-github) — owns backup reliability
2. Ops Officer (spec-ops) — owns monitoring
3. Captain (main) — routes everything
4. Relay — human interface
5. Everyone else

## Error diagnosis

**"create-skill SKILL.md not found"**
- The source of truth for best practices is missing.
- CHECK: `ls /root/.openclaw/skills/create-skill/SKILL.md`
- FIX: The file should exist at that path. If deleted, it needs to be recreated
  (check openclaw-skills repo on GitHub for the backup).

**Skill directory exists but no SKILL.md**
- Empty skill directory — the skill was started but never written.
- ACTION: Either create the SKILL.md or delete the empty directory.

**Score disagreement between auditors**
- If two agents audit the same skill and disagree on score, defer to the
  stricter score. Better to over-improve than under-improve.

## Related
- `/create-skill` — the source of truth for best practices (READ THIS FIRST)
- `chart read skill-create-skill` — meta-skill creation context
- `chart read reading-repoman-skills-audit-20260518` — first audit that established the pattern
- `chart search "skill"` — all skill-related charts

Intent: Quality [I-quality].
