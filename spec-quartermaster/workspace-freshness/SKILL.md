---
name: workspace-freshness
version: 1.0.0
author: spec-quartermaster
scope: ↨ system
---

# Workspace Freshness Skill
## Purpose
Ensure agent workspaces remain **current with live configurations and documentation**.
- Detect stale files (unmodified >7d), broken symlinks, and missing required files.
- Proactively repair drift before agents misroute or run outdated intents.

## Intent
- Primary: **Observable [I13]** — transparent, auditable workspace state.
- Secondary: **Efficient [I06]** — automate drift detection, minimize manual review.
- Tertiary: **Reliable [I05]** — prevent agents from operating on stale context.

## Owner
Quartermaster (`spec-quartermaster`)

## Cron Binding
- **Schedule**: Weekly (Saturday) @ **06:00 UTC** via `/root/.openclaw/scripts/workspace-freshness-cron.sh`.
- **Output**: Appends results to `/root/.openclaw/logs/workspace-freshness.log`.
- **Critical Threshold**: Counts agents with `freshness_score < 4`; charts `issue-workspace-freshness-YYYYMMDD` if any found.

## Scan Procedure
### 1. **Freshness Check**
- **Metrics Collected per Agent**:
  - `last_edit_age` (days since workspace file edited)
  - `agent_live_config_health` (matches `openclaw.json`)
  - `tool_skill_health` (TOOLS.md count vs actual skills/)
  - `required_files_present` (SOUL.md, AGENTS.md, TOOLS.md, MEMORY.md, IDENTITY.md)
  - `symlink_health` (broken links)
- **Scoring**: Each agent scored **1-10** (`freshness_score`); **≤4** = **critical stale**.

### 2. **Pattern Learning**
- **Frequency Analysis**: Track which workspaces go stale fastest (e.g., `spec-strategy` → **high turnaround**, `spec-historian` → **low**).
- **Root Causes**:
  - Missing files (lack of `MEMORY.md`)
  - Model race conditions (switching between Gemini/Codex)
  - Broken symlinks (reorg without cleanup)

### 3. **Self-Improvement**
- **Trend Tracking**: Weekly `freshness_score` trend line; chart drops below 7.
- **Feedback Mechanism**:
  - If `>2 agents` critical in a workspace, file `issue: fix-workspace-OWNER`.
  - If **same agent** critical **2 weeks in a row**, escalate to **Reactor**.

## Skill Evolution Plan
### Version 1.X → 2.0
- **Add**: Predictive stale alerts based on edit velocity decay.
- **Add**: Auto-remediation: stale SOUL.md pull from `openclaw.json`.
- **Add**: Broken-link repair via symlink recreation.

## Dependencies
### MCP Tools
- None (self-contained)

### Host Tools
- Python 3.10+ (`pathlib`, `datetime`)
- `jq` (for JSON parsing critical threshold)
- `chart` (for issue creation)

## Verification
- Daily log: `/root/.openclaw/logs/workspace-freshness.log`
- Weekly trend: Add `stale-workspace-trend-YYYYMMDD` chart

## Sample Output (JSON)
```json
{
  "agent": "spec-strategy",
  "last_edit_age": 18,
  "agent_live_config_health": true,
  "tool_skill_health": false, // TOOLS.md lists 8, skills/ has 6
  "required_files_present": true,
  "symlink_health": true,
  "freshness_score": 3, // ❌ Critical stale
  "recommendation": "Repair TOOLS.md or archive 2 orphaned skills."
}
```

## Next Steps
1. **Restore Chart Tooling**: Ensure `chart` CLI available for issue creation.
2. **Prime Skill**: Run first analytics pass to seed workspace metrics.
3. **Monitor Trends**: Begin tracking weekly `freshness_score` per agent.