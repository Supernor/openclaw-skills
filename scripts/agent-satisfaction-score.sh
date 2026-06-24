#!/usr/bin/env python3
"""agent-satisfaction-score.py — Honest agent satisfaction scoring.

Policy: No propaganda in metrics. If we don't have per-agent data,
the score is UNKNOWN (?), not a comfortable default.
System-wide signals are system scores, not agent scores.

Usage:
  agent-satisfaction-score.py              # human-readable report
  agent-satisfaction-score.py --json       # machine-readable
  agent-satisfaction-score.py --agent relay # single agent detail
"""

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# ── Config ──
COMPOSE_DIR = "/root/openclaw"
OPS_DB = "/root/.openclaw/ops.db"
HEALTH_BUFFER = "/root/.openclaw/health/buffer.jsonl"
LOAD_HISTORY = "/root/.openclaw/logs/agent-load-history.jsonl"
ENGINE_TRUST = "/root/.openclaw/engine-trust.jsonl"

AGENTS = [
    ("relay",              "Relay"),
    ("main",               "Captain"),
    ("spec-projects",      "Scribe"),
    ("spec-github",        "Repo-Man"),
    ("spec-dev",           "Dev"),
    ("spec-reactor",       "Reactor Mgr"),
    ("spec-browser",       "Navigator"),
    ("spec-research",      "Research"),
    ("spec-security",      "Security"),
    ("spec-ops",           "Ops Officer"),
    ("spec-design",        "Designer"),
    ("spec-systems",       "Sys Engineer"),
    ("spec-comms",         "Comms Officer"),
    ("spec-strategy",      "Strategist"),
    ("spec-quartermaster", "Quartermaster"),
    ("spec-historian",     "Historian"),
    ("eoin",               "Eoin"),
    ("spec-realist",       "Realist"),
]

INTENT_GROUPS = {
    "EXECUTION":  [("I01","Accurate"), ("I03","Competent"), ("I05","Reliable"), ("I06","Efficient"), ("I07","Resourceful")],
    "RESILIENCE": [("I08","Resilient"), ("I11","Trusted"), ("I15","Recoverable")],
    "GROWTH":     [("I09","Growing"), ("I14","Adaptive"), ("I17","Autonomous"), ("I18","Informed")],
    "CONNECTION": [("I02","Understood"), ("I04","Responsive"), ("I10","Connected")],
    "AWARENESS":  [("I12","Aware"), ("I13","Observable"), ("I16","Secure"), ("I19","Coherent")],
}

ALL_INTENTS = []
for group in INTENT_GROUPS.values():
    ALL_INTENTS.extend(group)
ALL_INTENTS.sort(key=lambda x: int(x[0][1:]))


def ws_path(agent_id):
    if agent_id == "main":
        return Path("/root/.openclaw/workspace")
    return Path(f"/root/.openclaw/workspace-{agent_id}")


APS_PROJECTS_DIR = Path("/root/adaptive-project-system/projects")


def scan_aps_projects():
    """Scan APS projects for health signals.

    Returns dict with active, stalled, overdue_review counts and per-project details.
    """
    result = {"active": 0, "stalled": 0, "overdue_review": 0, "total": 0, "projects": []}

    if not APS_PROJECTS_DIR.exists():
        return result

    now = datetime.now(timezone.utc)

    for project_dir in APS_PROJECTS_DIR.iterdir():
        if not project_dir.is_dir():
            continue

        project_md = project_dir / "project.md"
        decision_log = project_dir / "decision-log.md"

        if not project_md.exists():
            continue

        result["total"] += 1
        project_info = {"name": project_dir.name, "status": "unknown", "stalled": False, "overdue": False}

        # Parse status from project.md
        try:
            content = project_md.read_text(errors="ignore")
            # Find status after "## Status" header
            lines = content.split("\n")
            in_status = False
            for line in lines:
                if line.strip().lower().startswith("## status"):
                    in_status = True
                    continue
                if in_status and line.strip():
                    stripped = line.strip().lower()
                    # Handle "active — notes" format
                    first_word = stripped.split()[0].rstrip("—-,") if stripped else ""
                    if first_word in ("active", "proposed", "paused", "completed", "retired"):
                        project_info["status"] = first_word
                    in_status = False
                    break
            # Find review cadence
            cadence_days = 30  # default monthly
            if "bi-weekly" in content.lower():
                cadence_days = 14
            elif "weekly" in content.lower():
                cadence_days = 7
            elif "quarterly" in content.lower():
                cadence_days = 90
            project_info["cadence_days"] = cadence_days
        except Exception:
            pass

        if project_info["status"] == "active":
            result["active"] += 1

        # Check decision-log recency
        if decision_log.exists():
            try:
                log_content = decision_log.read_text(errors="ignore")
                # Find most recent date in decision log (## YYYY-MM-DD format)
                dates = re.findall(r"##\s+(\d{4}-\d{2}-\d{2})", log_content)
                if dates:
                    latest = max(dates)
                    latest_dt = datetime.strptime(latest, "%Y-%m-%d").replace(tzinfo=timezone.utc)
                    days_since = (now - latest_dt).days
                    project_info["days_since_decision"] = days_since
                    project_info["latest_decision"] = latest

                    cadence = project_info.get("cadence_days", 30)
                    if days_since > cadence and project_info["status"] == "active":
                        project_info["overdue"] = True
                        result["overdue_review"] += 1
                    if days_since > cadence * 2 and project_info["status"] == "active":
                        project_info["stalled"] = True
                        result["stalled"] += 1
            except Exception:
                pass
        elif project_info["status"] == "active":
            # Active project with no decision log = stalled
            project_info["stalled"] = True
            result["stalled"] += 1

        result["projects"].append(project_info)

    return result


def scan_agent_journals(agent_id):
    """Scan agent memory dir for journal files and count documented actions.
    Returns dict with journal_count, action_count, date_range, latest_date."""
    mem_dir = ws_path(agent_id) / "memory"
    result = {"journal_count": 0, "action_count": 0, "latest_date": None, "date_range_days": 0}
    if not mem_dir.exists():
        return result

    dates = []
    action_count = 0
    journal_files = [f for f in mem_dir.iterdir() if f.suffix == ".md" and f.is_file()]
    result["journal_count"] = len(journal_files)

    for jf in journal_files:
        # Extract dates from filenames like 2026-03-14.md
        date_match = re.match(r"(\d{4}-\d{2}-\d{2})", jf.stem)
        if date_match:
            try:
                dates.append(datetime.strptime(date_match.group(1), "%Y-%m-%d"))
            except ValueError:
                pass
        # Count bullet-point actions (lines starting with - or *)
        try:
            text = jf.read_text(errors="ignore")
            action_count += len(re.findall(r"^\s*[-*]\s+\S", text, re.MULTILINE))
        except Exception:
            pass

    result["action_count"] = action_count
    if dates:
        dates.sort()
        result["latest_date"] = dates[-1].strftime("%Y-%m-%d")
        result["date_range_days"] = (dates[-1] - dates[0]).days + 1

    return result


def run(cmd, timeout=30):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except Exception:
        return ""


def load_json_lines(path):
    entries = []
    if not os.path.exists(path):
        return entries
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    entries.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return entries


# ── Data collection (one pass) ──

def collect_agent_data():
    data = {}

    # Load history — latest snapshot per agent
    load_entries = load_json_lines(LOAD_HISTORY)
    latest_load = {}
    if load_entries:
        last = load_entries[-1]  # most recent snapshot
        for a in last.get("agents", []):
            latest_load[a["agent"]] = a

    # Session data from gateway
    for agent_id, agent_name in AGENTS:
        d = {"id": agent_id, "name": agent_name}
        ws = ws_path(agent_id)

        # Load history
        load = latest_load.get(agent_id, {})
        d["ctx_pct"] = load.get("pct", None)
        d["tokens"] = load.get("tokens", None)
        d["context_window"] = load.get("context", None)
        d["state"] = load.get("state", None)
        d["model"] = load.get("model", None)

        # Session count from host filesystem (NOT docker compose exec — that takes 7.6s per agent)
        # Session files are at /root/.openclaw/agents/<id>/sessions/*.jsonl
        try:
            session_dir = Path(f"/root/.openclaw/agents/{agent_id}/sessions")
            if session_dir.exists():
                session_files = list(session_dir.glob("*.jsonl"))
                d["session_count"] = len(session_files)
                d["session_ctx_pct"] = 0  # Would need to parse JSONL to get context %, skip for speed
            else:
                d["session_count"] = 0
                d["session_ctx_pct"] = 0
        except Exception:
            d["session_count"] = None
            d["session_ctx_pct"] = None

        # Journal/memory analysis
        journal = scan_agent_journals(agent_id)
        d["journal_count"] = journal["journal_count"]
        d["action_count"] = journal["action_count"]
        d["journal_latest"] = journal["latest_date"]
        d["journal_range_days"] = journal["date_range_days"]

        # Workspace analysis
        d["has_soul"] = (ws / "SOUL.md").exists()
        d["has_tools"] = (ws / "TOOLS.md").exists()
        d["has_memory"] = (ws / "MEMORY.md").exists()
        d["has_identity"] = (ws / "IDENTITY.md").exists()

        if d["has_soul"]:
            soul_text = (ws / "SOUL.md").read_text(errors="ignore")
            d["soul_lines"] = soul_text.count("\n") + 1
            # Count boundary statements
            import re
            boundary_patterns = r"(?i)(you do not|not your|never |don.t |outside your|you cannot|you can.t|must not|off.limits)"
            d["soul_boundaries"] = len(re.findall(boundary_patterns, soul_text))
            d["soul_has_intent_ref"] = "intent-framework" in soul_text.lower()
        else:
            d["soul_lines"] = 0
            d["soul_boundaries"] = 0
            d["soul_has_intent_ref"] = False

        # Skills
        skills_dir = ws / "skills"
        if skills_dir.exists():
            d["skill_count"] = len([x for x in skills_dir.iterdir() if x.is_dir()])
            # Count intent-tagged skills
            tagged = 0
            for skill_dir in skills_dir.iterdir():
                skill_md = skill_dir / "SKILL.md"
                if skill_md.exists():
                    content = skill_md.read_text(errors="ignore")
                    if "intent:" in content.lower():
                        tagged += 1
            d["skills_tagged"] = tagged
        else:
            d["skill_count"] = 0
            d["skills_tagged"] = 0

        # Auth profiles from host filesystem (NOT docker compose exec — too slow)
        # Auth profiles are bind-mounted at /root/.openclaw/agents/<id>/agent/auth-profiles.json
        try:
            raw = ""
            auth_path = Path(f"/root/.openclaw/agents/{agent_id}/agent/auth-profiles.json")
            if auth_path.exists():
                raw = auth_path.read_text(errors="ignore").strip()
            if raw:
                profiles = json.loads(raw)
                prof_list = profiles.get("profiles", {})
                d["model_providers"] = len(prof_list)
                d["has_fallback"] = len(prof_list) > 1
                # Count errors from usage stats
                stats = profiles.get("usageStats", {})
                total_errors = sum(v.get("errorCount", 0) for v in stats.values())
                d["model_errors"] = total_errors
            else:
                d["model_providers"] = None
                d["has_fallback"] = None
                d["model_errors"] = None
        except Exception:
            d["model_providers"] = None
            d["has_fallback"] = None
            d["model_errors"] = None

        # APS project health (Scribe-specific signal)
        if agent_id == "spec-projects":
            d["aps_health"] = scan_aps_projects()
        else:
            d["aps_health"] = None

        data[agent_id] = d

    return data


def score_agent(d):
    """Score all 19 intents for one agent. Returns dict of {intent_id: (score, reason)}.
    Score is int 0-10 or None for unknown."""

    scores = {}

    # Helper
    def clamp(v):
        if v is None: return None
        return max(0, min(10, v))

    agent_id = d["id"]

    # ── I01 ACCURATE: Do we have evidence this agent produces correct output? ──
    # Without per-agent task success data, we can only check model errors + journal activity
    if d.get("model_errors") is not None:
        errs = d["model_errors"]
        if d.get("session_count") and d["session_count"] > 0:
            s = 7
            if errs > 3: s = 4
            elif errs > 0: s = 6
            reason = f"{errs} model errors, {d['session_count']} sessions"
        else:
            s = None
            reason = "no session activity"
    else:
        s = None
        reason = "no data"
    # Journal fallback: if no session data but journals exist, use action count as evidence
    if s is None and d["action_count"] > 0:
        actions = d["action_count"]
        if actions >= 20: s = 7
        elif actions >= 10: s = 6
        elif actions >= 3: s = 5
        else: s = 4
        reason = f"{actions} logged actions across {d['journal_count']} journals"
    scores["I01"] = (clamp(s), reason)

    # ── I02 UNDERSTOOD: Does the agent know its role and boundaries? ──
    if d["has_soul"]:
        s = 5
        if d["soul_lines"] > 50: s += 2
        if d["soul_lines"] > 100: s += 1
        if d["soul_boundaries"] > 0: s += 2
        if d["soul_boundaries"] == 0: s -= 1
        reason = f"SOUL {d['soul_lines']}L, {d['soul_boundaries']} boundaries"
    else:
        s = 0
        reason = "no SOUL.md"
    scores["I02"] = (clamp(s), reason)

    # ── I03 COMPETENT: Skills + tools documentation ──
    skills = d["skill_count"]
    s = 5
    if 3 <= skills <= 7: s = 9
    elif 1 <= skills < 3: s = 6
    elif 8 <= skills <= 12: s = 8
    elif skills > 12: s = 7  # too many can mean unfocused
    elif skills == 0: s = 2
    if not d["has_tools"]: s -= 1
    reason = f"{skills} skills, TOOLS.md:{d['has_tools']}"
    scores["I03"] = (clamp(s), reason)

    # ── I04 RESPONSIVE: Has the agent actually responded to requests? ──
    sc = d.get("session_count")
    if sc is not None and sc > 0:
        s = 5
        if sc > 3: s = 8
        elif sc > 1: s = 7
        reason = f"{sc} sessions"
    elif sc == 0:
        s = 2
        reason = "0 sessions — never used"
    else:
        s = None
        reason = "no session data"
    # Journal fallback: journals prove the agent was active even without session data
    if s is None and d["journal_count"] > 0:
        jc = d["journal_count"]
        if jc >= 10: s = 7
        elif jc >= 5: s = 6
        elif jc >= 2: s = 5
        else: s = 4
        reason = f"{jc} journal entries (latest: {d['journal_latest'] or '?'})"
    scores["I04"] = (clamp(s), reason)

    # ── I05 RELIABLE: Consistent delivery — sessions + model stability ──
    if d.get("session_count") is not None and d.get("model_errors") is not None:
        sc = d["session_count"]
        errs = d["model_errors"]
        ctx = d.get("ctx_pct") or d.get("session_ctx_pct") or 0
        s = 5
        if sc > 3: s += 1
        if errs == 0: s += 2
        elif errs > 3: s -= 2
        if ctx > 85: s -= 2  # overloaded = unreliable
        elif ctx < 50: s += 1
        reason = f"{sc} sessions, {errs} errors, ctx {ctx}%"
    else:
        s = None
        reason = "no data"
    # Journal fallback: consistent journaling = evidence of reliability
    if s is None and d["journal_range_days"] > 0:
        days = d["journal_range_days"]
        jc = d["journal_count"]
        if days >= 7 and jc >= 5: s = 7
        elif days >= 3 and jc >= 3: s = 6
        elif jc >= 2: s = 5
        else: s = 4
        reason = f"{jc} journals over {days} days"
    scores["I05"] = (clamp(s), reason)

    # ── I06 EFFICIENT: Context usage (lower = more efficient) ──
    ctx = d.get("ctx_pct") or d.get("session_ctx_pct")
    if ctx is not None:
        if ctx <= 10: s = 10
        elif ctx <= 25: s = 9
        elif ctx <= 40: s = 8
        elif ctx <= 55: s = 7
        elif ctx <= 70: s = 6
        elif ctx <= 85: s = 4
        else: s = 2
        reason = f"context {ctx}%"
    else:
        s = None
        reason = "no context data"
    scores["I06"] = (clamp(s), reason)

    # ── I07 RESOURCEFUL: Uses available tools effectively ──
    skills = d["skill_count"]
    s = 5
    if skills > 0: s += 2
    if d["has_memory"]: s += 1
    if d["has_tools"]: s += 1
    if skills == 0: s = 3
    # Journal activity shows the agent actually uses its resources
    if d["action_count"] >= 10: s += 1
    reason = f"{skills} skills, MEMORY:{d['has_memory']}, TOOLS:{d['has_tools']}"
    if d["action_count"] > 0:
        reason += f", {d['action_count']} logged actions"
    scores["I07"] = (clamp(s), reason)

    # ── I08 RESILIENT: Can survive failures ──
    fb = d.get("has_fallback")
    errs = d.get("model_errors")
    if fb is not None:
        s = 5
        if fb: s += 3
        if errs is not None:
            if errs == 0: s += 2
            elif errs > 5: s -= 3
        reason = f"fallback:{fb}, errors:{errs}"
    else:
        s = None
        reason = "no auth profile data"
    scores["I08"] = (clamp(s), reason)

    # ── I09 GROWING: Evidence of skill/capability investment ──
    skills = d["skill_count"]
    soul = d["soul_lines"]
    s = 5
    if skills > 2: s += 2
    if soul > 80: s += 2
    if skills == 0 and soul < 30: s = 2
    reason = f"{skills} skills, SOUL {soul}L"
    scores["I09"] = (clamp(s), reason)

    # ── I10 CONNECTED: Can reach and be reached ──
    sc = d.get("session_count")
    if sc is not None:
        if sc > 5: s = 9
        elif sc > 2: s = 7
        elif sc > 0: s = 6
        else: s = 3
        reason = f"{sc} sessions"
    else:
        s = None
        reason = "no session data"
    # Journal fallback: journals prove connectivity even without live sessions
    if s is None and d["journal_count"] > 0:
        jc = d["journal_count"]
        if jc >= 10: s = 7
        elif jc >= 5: s = 6
        elif jc >= 2: s = 5
        else: s = 4
        reason = f"{jc} journal entries spanning {d['journal_range_days']}d"
    scores["I10"] = (clamp(s), reason)

    # ── I11 TRUSTED: Earned track record — only from measured evidence ──
    # This is the hardest to score honestly. Without per-agent task tracking,
    # trust is mostly unknown.
    sc = d.get("session_count")
    errs = d.get("model_errors")
    if sc is not None and sc > 0 and errs is not None:
        s = 5
        if errs == 0: s += 2
        elif errs > 3: s -= 2
        ctx = d.get("ctx_pct") or d.get("session_ctx_pct") or 0
        if ctx < 50: s += 1
        reason = f"{sc} sessions, {errs} errors"
        # Agents with no observed failures get a cautious score, not a high one
        if sc <= 1:
            s = min(s, 6)
            reason += " (limited data)"
    elif sc == 0:
        s = None
        reason = "never used — no trust earned"
    else:
        s = None
        reason = "no data"
    # Journal fallback: documented work history = some trust evidence
    if s is None and d["action_count"] >= 5:
        actions = d["action_count"]
        days = d["journal_range_days"]
        if actions >= 20 and days >= 7: s = 6
        elif actions >= 10: s = 5
        else: s = 4
        reason = f"{actions} logged actions over {days}d (journal-based, limited)"
    scores["I11"] = (clamp(s), reason)

    # ── I12 AWARE: Knows own state ──
    s = 5
    if d["has_identity"]: s += 1
    if d["has_soul"] and d["soul_lines"] > 50: s += 1
    ctx = d.get("ctx_pct") or d.get("session_ctx_pct")
    if ctx is not None:
        if ctx > 85: s -= 2  # overloaded agents can't be self-aware
        elif ctx < 50: s += 1
    # Only Relay has heartbeat
    if agent_id == "relay": s += 2
    reason = f"IDENTITY:{d['has_identity']}, SOUL:{d['soul_lines']}L"
    if ctx is not None:
        reason += f", ctx:{ctx}%"
    scores["I12"] = (clamp(s), reason)

    # ── I13 OBSERVABLE: Can we see what it's doing? ──
    # Health buffer, load tracking, session data all contribute
    s = 5
    sc = d.get("session_count")
    if sc is not None and sc > 0: s += 2  # sessions = we can see it
    # Check if load tracking has data for this agent
    ctx = d.get("ctx_pct")
    if ctx is not None: s += 1  # appears in load history
    if sc is not None and sc == 0 and ctx in (None, 0):
        s = 3  # invisible agent
        reason = "no sessions, no load data — invisible"
    else:
        reason = f"sessions:{sc}, in load history:{ctx is not None}"
    scores["I13"] = (clamp(s), reason)

    # ── I14 ADAPTIVE: Evolving with intent framework ──
    tagged = d["skills_tagged"]
    skills = d["skill_count"]
    if skills > 0:
        pct = tagged / skills * 100
        if pct >= 90: s = 9
        elif pct >= 50: s = 7
        elif pct > 0: s = 5
        else: s = 3
        reason = f"{tagged}/{skills} skills tagged ({int(pct)}%)"
    elif d["has_soul"] and d.get("soul_has_intent_ref"):
        s = 5
        reason = "no skills, but intent-aware SOUL"
    else:
        s = 3
        reason = "no skills, no intent refs"
    scores["I14"] = (clamp(s), reason)

    # ── I15 RECOVERABLE: Can bounce back from failures ──
    fb = d.get("has_fallback")
    if fb is not None:
        s = 5
        if fb: s += 3
        # Session maintenance cron exists system-wide
        s += 1  # cron exists
        reason = f"fallback:{fb}"
    else:
        s = None
        reason = "no auth data"
    scores["I15"] = (clamp(s), reason)

    # ── I16 SECURE: Protects against harm ──
    s = 5
    # Config perms
    try:
        config_mode = oct(os.stat("/root/.openclaw/openclaw.json").st_mode)[-3:]
        env_mode = oct(os.stat("/root/openclaw/.env").st_mode)[-3:]
    except Exception:
        config_mode = "?"
        env_mode = "?"
    if config_mode == "600": s += 1
    if env_mode == "600": s += 1
    if d["soul_boundaries"] > 0: s += 1
    if d["soul_boundaries"] > 3: s += 1
    reason = f"config:{config_mode}, .env:{env_mode}, {d['soul_boundaries']} boundaries"
    scores["I16"] = (clamp(s), reason)

    # ── I17 AUTONOMOUS: Can self-govern within boundaries ──
    # Primary signal (added 2026-06-12): measured autonomy from ops.db
    # agent_performance — tasks completed in last 30 days without a human
    # intervention. Falls back to the old skills/fallback proxy when the
    # agent has no task history (honest-? policy).
    auto_done, auto_interventions = None, None
    try:
        import sqlite3 as _sq
        with _sq.connect(OPS_DB) as _db:
            row = _db.execute(
                "SELECT SUM(tasks_completed), SUM(human_interventions) "
                "FROM agent_performance WHERE agent=? "
                "AND date >= date('now','-30 day')", (agent_id,)).fetchone()
        if row and row[0]:
            auto_done, auto_interventions = int(row[0]), int(row[1] or 0)
    except Exception:
        pass
    skills = d["skill_count"]
    fb = d.get("has_fallback")
    errs = d.get("model_errors")
    if auto_done:
        rate = max(0.0, (auto_done - auto_interventions) / auto_done)
        s = round(rate * 8)  # 0..8 from measured autonomy
        if skills >= 3: s += 1
        if fb: s += 1
        reason = (f"{auto_done} tasks/30d, {auto_interventions} interventions "
                  f"(autonomy {rate:.0%}), {skills} skills, fallback:{fb}")
    elif skills > 0 and fb is not None:
        s = 5
        if skills >= 3: s += 2
        if fb: s += 1
        if errs is not None and errs == 0: s += 1
        reason = f"no task history; proxy: {skills} skills, fallback:{fb}, errors:{errs}"
    elif skills == 0:
        s = 2
        reason = f"0 skills — can't self-govern"
    else:
        s = None
        reason = "no data"
    scores["I17"] = (clamp(s), reason)

    # ── I18 INFORMED: This agent's access to shared knowledge ──
    # NOT system-wide chart count. Does THIS agent have memory + tools docs?
    s = 5
    if d["has_memory"]: s += 2
    if d["has_tools"]: s += 1
    if d["has_soul"] and d["soul_has_intent_ref"]: s += 1
    if d["skill_count"] > 0: s += 1
    reason = f"MEMORY:{d['has_memory']}, TOOLS:{d['has_tools']}, intent-ref:{d.get('soul_has_intent_ref', False)}"
    scores["I18"] = (clamp(s), reason)

    # ── I19 COHERENT: Internal consistency ──
    s = 5
    if d["has_soul"]: s += 1
    if d["has_tools"]: s += 1
    if d["has_memory"]: s += 1
    if d["has_identity"]: s += 1
    if d.get("soul_has_intent_ref"): s += 1
    else: s -= 1
    if not d["has_soul"]: s = 1
    parts = []
    for f in ["has_soul", "has_tools", "has_memory", "has_identity"]:
        label = f.replace("has_", "").upper()
        parts.append(f"{label}:{'y' if d[f] else 'n'}")
    reason = ", ".join(parts)
    scores["I19"] = (clamp(s), reason)

    # ── APS Project Health adjustments (Scribe only) ──
    aps = d.get("aps_health")
    if aps and agent_id == "spec-projects" and aps["total"] > 0:
        # I05 RELIABLE: drops if projects are stalled (no decision-log activity)
        if aps["stalled"] > 0:
            s05, r05 = scores.get("I05", (None, ""))
            if s05 is not None:
                penalty = min(3, aps["stalled"])  # -1 per stalled, max -3
                scores["I05"] = (clamp(s05 - penalty), f"{r05}; {aps['stalled']} stalled projects")

        # I01 ACCURATE: drops if promoted projects have incomplete methods
        incomplete = sum(1 for p in aps["projects"] if p["status"] == "active" and p.get("stalled"))
        if incomplete > 0:
            s01, r01 = scores.get("I01", (None, ""))
            if s01 is not None:
                scores["I01"] = (clamp(s01 - 1), f"{r01}; {incomplete} active projects need attention")

        # I13 OBSERVABLE: boosted by having active, healthy projects
        healthy = aps["active"] - aps["stalled"]
        if healthy > 0:
            s13, r13 = scores.get("I13", (None, ""))
            if s13 is not None:
                boost = min(2, healthy)  # +1 per healthy active project, max +2
                scores["I13"] = (clamp(s13 + boost), f"{r13}; {healthy} healthy APS projects")

    return scores


def render_bar(score):
    if score is None:
        return "?????.?????"
    return "#" * score + "." * (10 - score)


def render_score(score):
    if score is None:
        return " ?"
    return f"{score:2d}"


def main():
    args = sys.argv[1:]
    mode = "report"
    filter_agent = None
    if "--json" in args:
        mode = "json"
    if "--agent" in args:
        idx = args.index("--agent")
        if idx + 1 < len(args):
            filter_agent = args[idx + 1]

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Collect
    agent_data = collect_agent_data()

    # Score
    all_scores = {}
    for agent_id, _ in AGENTS:
        if agent_id in agent_data:
            all_scores[agent_id] = score_agent(agent_data[agent_id])

    if mode == "json":
        output = {"timestamp": now, "framework": "I01-I19 v5 (no-propaganda)", "agents": {}}
        for agent_id, agent_name in AGENTS:
            if filter_agent and agent_id != filter_agent:
                continue
            scores = all_scores.get(agent_id, {})
            known = [s for _, (s, _) in scores.items() if s is not None]
            avg = sum(known) / len(known) if known else None
            unknown = sum(1 for _, (s, _) in scores.items() if s is None)
            output["agents"][agent_id] = {
                "name": agent_name,
                "avg": round(avg, 1) if avg else None,
                "unknown_intents": unknown,
                "intents": {k: {"score": s, "reason": r} for k, (s, r) in scores.items()},
            }
        print(json.dumps(output, indent=2))
        return

    # Report mode
    print(f"+{'=' * 67}+")
    print(f"|  AGENT SATISFACTION REPORT — {now}  |")
    print(f"|  Policy: No propaganda. ? = no data. Scores are earned.{' ' * 11}|")
    print(f"+{'=' * 67}+")
    print()

    for agent_id, agent_name in AGENTS:
        if filter_agent and agent_id != filter_agent:
            continue
        d = agent_data.get(agent_id)
        if not d:
            print(f"+-- {agent_name:14s} ({agent_id:12s}) -- NO DATA")
            print()
            continue

        scores = all_scores.get(agent_id, {})
        known_scores = [s for _, (s, _) in scores.items() if s is not None]
        unknown_count = sum(1 for _, (s, _) in scores.items() if s is None)

        if known_scores:
            avg = sum(known_scores) / len(known_scores)
            avg_str = f"{avg:.1f}"
        else:
            avg_str = "?"

        ctx = d.get("ctx_pct") or d.get("session_ctx_pct") or 0
        state = "ok"
        if ctx and ctx > 70: state = "STRAINED"
        if ctx and ctx > 85: state = "OVERLOADED"

        print(f"+-- {agent_name:14s} ({agent_id:17s}) -- avg: {avg_str}/10 -- ctx: {ctx}% {state}")
        if unknown_count > 0:
            print(f"|   ({unknown_count} intents have no data — not scored)")

        for iid, iname in ALL_INTENTS:
            s, reason = scores.get(iid, (None, "not scored"))
            bar = render_bar(s)
            score_str = render_score(s)
            print(f"|  {iname:12s} [{iid:3s}] [{bar}] {score_str}  {reason}")

        print(f"+{'─' * 67}")
        print()

    # System summary
    print(f"+-- SYSTEM SUMMARY")
    print(f"|")

    fleet_avgs = []
    for agent_id, _ in AGENTS:
        scores = all_scores.get(agent_id, {})
        known = [s for _, (s, _) in scores.items() if s is not None]
        if known:
            fleet_avgs.append(sum(known) / len(known))

    if fleet_avgs:
        fleet_avg = sum(fleet_avgs) / len(fleet_avgs)
        print(f"|  Fleet average: {fleet_avg:.1f}/10 ({len(AGENTS)} agents)")
    else:
        print(f"|  Fleet average: ? (no data)")

    total_skills = sum(agent_data.get(a, {}).get("skill_count", 0) for a, _ in AGENTS)
    total_unknown = sum(
        sum(1 for _, (s, _) in all_scores.get(a, {}).items() if s is None)
        for a, _ in AGENTS
    )
    print(f"|  Total skills: {total_skills}")
    print(f"|  Unknown scores: {total_unknown}/{len(AGENTS) * 19} ({total_unknown / (len(AGENTS) * 19) * 100:.0f}% blind spots)")
    print(f"|")

    # Group averages (only from known scores)
    for group_name, intents in INTENT_GROUPS.items():
        group_scores = []
        for agent_id, _ in AGENTS:
            for iid, _ in intents:
                s, _ = all_scores.get(agent_id, {}).get(iid, (None, ""))
                if s is not None:
                    group_scores.append(s)
        if group_scores:
            gavg = sum(group_scores) / len(group_scores)
            ids = " ".join(i for i, _ in intents)
            print(f"|  {group_name:12s} avg: {gavg:.1f}/10  ({ids})")
        else:
            print(f"|  {group_name:12s} avg: ?/10  (no data)")

    print(f"+{'─' * 67}")


if __name__ == "__main__":
    main()
