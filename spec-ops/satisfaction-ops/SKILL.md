# Satisfaction Ops

**Owner**: Ops Officer (`spec-ops`)
**Triggers**:
- Cron: `satisfaction-heal` @ 07:45 UTC daily
- Cron: `satisfaction-improve` @ 07:30 UTC daily
**Intents**: [Observable], [Resilient], [Reliable], [Informed]
**Purpose**: Monitor, heal, and improve agent satisfaction scores autonomously. Track trends, document fixes, and self-learn from effectiveness.

---

## **Procedures**

### **1. `satisfaction-heal`**
**Purpose**: Detect and fix satisfaction threshold breaches.

#### **Schedule**
- Daily @ 07:45 UTC.
- On-demand with `--dry-run` (preview) or `--apply` (execute).

#### **Inputs**
- Satisfaction scores (`/root/.openclaw/scripts/agent-satisfaction-score.py --json`).
- Fleet alignment (`/root/.openclaw/scripts/intent-audit-deep --json`).
- Thresholds (defined in `THRESHOLDS` dict).

#### **Outputs**
- Actions logged to `/root/.openclaw/logs/satisfaction-heal.log`.
- JSON report (if `--json` flag used).
- Skill-gap ideas proposed to **Strategist** via `strategist-tools.py`.

#### **Fixes Applied**
| Intent               | Threshold | Action               | Description                                                                                     |
|----------------------|-----------|----------------------|-------------------------------------------------------------------------------------------------|
| `I06: Efficient`     | 3         | `reset_session`      | Resets bloated sessions via `session-maintenance.sh`.                                          |
| `I05: Reliable`      | 4         | `flag_errors`        | Flags chronic errors for manual review.                                                        |
| `I02: Understood`    | 5         | `flag_soul_rewrite`  | Flags `SOUL.md` for clarity improvements.                                                      |
| `I03: Competent`     | 5         | `flag_skills_gap`    | Proposes skill-gap ideas to **Strategist**.                                                     |
| Fleet Average        | 6.0       | `system_alert`       | Alerts if fleet average falls below threshold.                                                  |
| Fleet Alignment      | 60%       | `flag_alignment`     | Logs alignment issues to `/root/.openclaw/logs/alignment-recommendations.log`.                  |

#### **Metrics Tracked**
- Agent-specific scores (e.g., `I06: Efficient`).
- Fleet average satisfaction and alignment.
- Count of threshold breaches and actions taken.

---

### **2. `satisfaction-improve`**
**Purpose**: Create targeted improvement tasks for the weakest agent.

#### **Schedule**
- Daily @ 07:30 UTC.

#### **Inputs**
- Ops database (`/root/.openclaw/ops.db`):
  - Recent tasks (last 7 days).
  - Agent schedule (`agent_schedule` table).

#### **Outputs**
- Tasks created in `ops.db` (`tasks` table) for **Captain**/**Reactor** dispatch.

#### **Fixes Applied**
| Fix Type            | Description                                                                                     | Task Example                                                                                     |
|---------------------|-------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| `diagnose_failures` | Analyzes high failure rates (blocked tasks).                                                   | "*Diagnose why `spec-ops` has a 25% failure rate.*"                                          |
| `optimize_speed`    | Optimizes agents with overruns (tasks exceeding time slots).                                   | "*Help `spec-ops` finish tasks within 15-minute slots.*"                                     |
| `activate`          | Activates inactive agents (no activity in 3+ days).                                            | "*Activate `spec-research` — no activity in 5 days.*"                                        |

#### **Metrics Tracked**
- Failure rate (`blocked tasks / total tasks`).
- Overrun count (tasks exceeding time slots).
- Inactivity (days since last task).

---

## **Self-Learning Components**

### **1. Trend Tracking**
- **SQL Table**: `satisfaction_trends` in `ops.db`.
```sql
CREATE TABLE IF NOT EXISTS satisfaction_trends (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id TEXT NOT NULL,
    intent TEXT NOT NULL,
    score REAL NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fix_applied TEXT,
    status TEXT DEFAULT 'open',
    UNIQUE(agent_id, intent, timestamp)
);
```
- **Queries**:
  - Weekly averages for each agent/intent.
  - Identify regressions (score drops after fixes).
  - Flag persistent low-scoring intents (e.g., `I06: Efficient` for `spec-ops`).

### **2. Fix Effectiveness**
- **Log Analysis**: Parse `/root/.openclaw/logs/satisfaction-heal.log` for:
  - **Fixes that worked**: E.g., `reset_session` improved `I06: Efficient` score by 1.2.
  - **Fixes that failed**: E.g., `flag_errors` had no impact on `spec-dev` reliability.
- **Feedback Loop**: Auto-propose new fixes or adjust thresholds based on effectiveness.

### **3. Idea Proposals**
- **Skill Gaps**: Uses `strategist-tools.py` to propose missing skills (e.g., "*Add skill for log rotation to improve `spec-ops` reliability*").
- **SOUL.md Improvements**: Flags agents with low `I02: Understood` scores for **Vision Holder** review.

---

## **Execution**

### **Cron Jobs**
| Script                     | Time  | Command                                                                              |
|----------------------------|-------|--------------------------------------------------------------------------------------|
| `satisfaction-heal.py`     | 07:45 | `python /root/.openclaw/scripts/satisfaction-heal.py --apply --json`               |
| `satisfaction-improve.py`  | 07:30 | `python /root/.openclaw/scripts/satisfaction-improve.py`                            |

### **Manual Triggers**
- **Heal Preview**: `python /root/.openclaw/scripts/satisfaction-heal.py --dry-run`.
- **Heal Apply**: `python /root/.openclaw/scripts/satisfaction-heal.py --apply`.
- **Force Improvement**: `python /root/.openclaw/scripts/satisfaction-improve.py`.

---

## **Escalation**
- **Fleet-Wide Issues**: If **fleet average < 6.0** or **alignment < 60%**, log a **bearing question** for the **Vision Holder**.
- **Persistent Failures**: If an agent’s score doesn’t improve after 3 fixes, flag for **React Review**.

---

## **Dependencies**
- `agent-satisfaction-score.py` (scoring).
- `intent-audit-deep` (fleet alignment).
- `ops.db` (task creation).
- `session-maintenance.sh` (session resets).
- `strategist-tools.py` (skill-gap ideas).