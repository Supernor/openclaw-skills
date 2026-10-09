---
name: chart-stale
version: 1.0.0
author: spec-quartermaster
scope: ↨ system
---

# Chart-Stale Skill
## Purpose
Monitor Chartroom hygiene by identifying, analyzing, and charting stale entries (no `Verified` field or last verified >14d ago). Improve over time by detecting recurring patterns (topic drift, re-verification gaps).

## Intent
- Primary: **Observable [I13]** — maintain transparent, auditable chart state.
- Secondary: **Efficient [I06]** — reduce manual review load.

## Owner
Quartermaster (`spec-quartermaster`).

## Cron Binding
- Schedule: Daily @ 6:00 UTC via `~/.openclaw/scripts/chart-stale-cron.sh`.
- Output: Appends results to `/root/.openclaw/logs/chart-stale.log`.

## Procedure
### Daily Run
1. **Scan**: `chart stale 14` lists entries without `Verified` field or stale verification (>14d).
2. **Capture**:
   - Redirect output to log.
   - Count: `grep -c 