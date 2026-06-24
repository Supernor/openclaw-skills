#!/usr/bin/env python3
"""ops-db.py — Query/mutate the OpenClaw operational database.
Both Claude Code (host) and agents (container) use this script.
All output is JSON for easy piping.

Usage:
  ops-db.py health snapshot                     # Record current provider health
  ops-db.py health latest                       # Latest status per provider
  ops-db.py health history [provider] [--limit N]  # Recent snapshots
  ops-db.py health trends [hours]               # Analytics: uptime, failures, resolution time

  ops-db.py incident open <title> [--provider X] [--severity X] [--desc "..."]
  ops-db.py incident close <id> [--resolution "..."]
  ops-db.py incident list [--open|--all]

  ops-db.py task create <agent> <summary> [--urgency X] [--context "..."] [--files '["..."]']
  ops-db.py task update <id> <status> [--result '{"..."}']
  ops-db.py task list [--status X] [--agent X]
  ops-db.py task get <id>

  ops-db.py notify <type> <provider> <message> [--reason X]
  ops-db.py notify list [--undelivered|--all] [--limit N]
  ops-db.py notify deliver <id>

  ops-db.py config log <json_line>              # Backfill a config-audit entry
  ops-db.py config recent [--limit N]

  ops-db.py kv get <key>
  ops-db.py kv set <key> <value>

  ops-db.py query "<SQL>"                       # Raw query (SELECT only)
  ops-db.py stats                               # Table row counts
  ops-db.py init                                # Re-initialize schema (safe, uses IF NOT EXISTS)
"""

import json
import os
import re
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone


# ── Path resolution ──

BASE = "/home/node/.openclaw"
if not os.path.isdir(BASE) and os.path.isdir("/root/.openclaw"):
    BASE = "/root/.openclaw"

DB_PATH = os.path.join(BASE, "ops.db")
INIT_SQL = os.path.join(BASE, "scripts", "ops-db-init.sql")


def error_exit(msg, code=1):
    print(json.dumps({"error": msg, "code": "invalid_input" if code == 1 else "internal_error"}), file=sys.stderr)
    sys.exit(code)


def auto_init():
    """Initialize DB from init SQL if DB doesn't exist."""
    if not os.path.isfile(DB_PATH) and os.path.isfile(INIT_SQL):
        with open(INIT_SQL, "r") as f:
            schema = f.read()
        conn = sqlite3.connect(DB_PATH)
        conn.execute("PRAGMA busy_timeout=5000")
        conn.executescript(schema)
        conn.close()


def get_conn():
    """Get a connection with WAL mode and foreign keys enabled."""
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA foreign_keys=ON;")
    conn.row_factory = sqlite3.Row
    return conn


def rows_to_json(rows):
    """Convert sqlite3.Row results to a list of dicts (matching sqlite3 -json output)."""
    return [dict(r) for r in rows]


def print_json(obj):
    """Print JSON to stdout."""
    print(json.dumps(obj))


def sq(sql, params=()):
    """Execute a SELECT query and return results as JSON list."""
    conn = get_conn()
    cur = conn.execute(sql, params)
    result = rows_to_json(cur.fetchall())
    conn.close()
    return result


def sq_exec(sql, params=()):
    """Execute a non-SELECT query."""
    conn = get_conn()
    conn.execute(sql, params)
    conn.commit()
    conn.close()


def sq_exec_return_scalar(sql, params=()):
    """Execute a query and return a single scalar value."""
    conn = get_conn()
    cur = conn.execute(sql, params)
    row = cur.fetchone()
    conn.close()
    return row[0] if row else None


_VALID_TABLES = frozenset([
    "health_snapshots", "config_changes", "incidents", "tasks",
    "notifications", "kv", "agent_results"
])


def sq_insert_return(table, insert_sql, params=()):
    """Insert a row and return it as JSON."""
    if table not in _VALID_TABLES:
        error_exit(f"Invalid table name: {table}", code=1)
    conn = get_conn()
    conn.execute(insert_sql, params)
    conn.commit()
    cur = conn.execute(f"SELECT * FROM {table} WHERE rowid = last_insert_rowid()")
    result = rows_to_json(cur.fetchall())
    conn.close()
    return result


def now_utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_args_after(args, start_index):
    """Parse --key value pairs from args starting at start_index. Returns dict."""
    opts = {}
    i = start_index
    while i < len(args):
        if args[i].startswith("--") and i + 1 < len(args):
            key = args[i][2:]
            opts[key] = args[i + 1]
            i += 2
        else:
            i += 1
    return opts


# ── HEALTH ──

def cmd_health(args):
    if len(args) < 1:
        error_exit("Usage: ops-db.py health <snapshot|latest|history|trends>")

    sub = args[0]

    if sub == "snapshot":
        mh_path = os.path.join(BASE, "model-health.json")
        if not os.path.isfile(mh_path):
            print_json({"error": "model-health.json not found"})
            sys.exit(1)

        with open(mh_path, "r") as f:
            mh = json.load(f)

        ts = now_utc()
        count = 0
        conn = get_conn()

        providers = mh.get("providers", {})
        for provider, data in providers.items():
            status = data.get("status", "healthy")
            reason = data.get("reason", "none") or "none"
            fcount = data.get("failureCount", 0)
            profiles = data.get("profiles", {})
            first_profile = next(iter(profiles.values()), {}) if profiles else {}
            ecount = first_profile.get("errorCount", 0)
            lused = first_profile.get("lastUsed", "")

            conn.execute(
                "INSERT INTO health_snapshots (ts, provider, status, reason, failure_count, error_count, last_used) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (ts, provider, status, reason, fcount, ecount, lused),
            )
            count += 1

        conn.commit()
        conn.close()
        print_json({"status": "ok", "inserted": count, "timestamp": ts})

    elif sub == "latest":
        print_json(sq("SELECT * FROM v_latest_health"))

    elif sub == "history":
        rest = args[1:]
        provider = None
        limit = 20
        i = 0
        while i < len(rest):
            if rest[i] == "--limit" and i + 1 < len(rest):
                try:
                    limit = int(rest[i + 1])
                except ValueError:
                    error_exit(f"Invalid limit value: {rest[i + 1]}")
                i += 2
            else:
                provider = rest[i]
                i += 1

        if provider:
            result = sq(
                "SELECT * FROM health_snapshots WHERE provider=? ORDER BY ts DESC LIMIT ?",
                (provider, limit),
            )
        else:
            result = sq(
                "SELECT * FROM health_snapshots ORDER BY ts DESC LIMIT ?",
                (limit,),
            )
        print_json(result)

    elif sub == "trends":
        try:
            hours = int(args[1]) if len(args) > 1 else 168
        except ValueError:
            error_exit(f"Invalid hours value: {args[1]}")
        try:
            result = subprocess.run(
                ["date", "-u", "-d", f"{hours} hours ago", "+%Y-%m-%dT%H:%M:%SZ"],
                capture_output=True, text=True, check=True,
            )
            cutoff = result.stdout.strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            cutoff = now_utc()

        conn = get_conn()

        total = conn.execute(
            "SELECT COUNT(*) FROM health_snapshots WHERE ts > ?", (cutoff,)
        ).fetchone()[0]

        failures = rows_to_json(conn.execute(
            "SELECT provider, COUNT(*) as failures, GROUP_CONCAT(DISTINCT reason) as reasons "
            "FROM health_snapshots WHERE ts > ? AND status != 'healthy' GROUP BY provider ORDER BY failures DESC",
            (cutoff,),
        ).fetchall())

        current = rows_to_json(conn.execute("SELECT * FROM v_latest_health").fetchall())

        rates = rows_to_json(conn.execute(
            "SELECT provider, COUNT(*) as total, "
            "SUM(CASE WHEN status != 'healthy' THEN 1 ELSE 0 END) as unhealthy, "
            "ROUND(100.0 * SUM(CASE WHEN status = 'healthy' THEN 1 ELSE 0 END) / COUNT(*), 1) as uptime_pct "
            "FROM health_snapshots WHERE ts > ? GROUP BY provider",
            (cutoff,),
        ).fetchall())

        incident_total = conn.execute(
            "SELECT COUNT(*) FROM incidents WHERE opened_at > ?", (cutoff,)
        ).fetchone()[0]

        incident_open = conn.execute(
            "SELECT COUNT(*) FROM v_open_incidents"
        ).fetchone()[0]

        avg_raw = conn.execute(
            "SELECT ROUND(AVG((julianday(closed_at) - julianday(opened_at)) * 1440), 1) "
            "FROM incidents WHERE opened_at > ? AND closed_at IS NOT NULL",
            (cutoff,),
        ).fetchone()[0]
        incident_avg_mins = avg_raw if avg_raw is not None else None

        notif_failures = conn.execute(
            "SELECT COUNT(*) FROM notifications WHERE ts > ? AND type='failure'",
            (cutoff,),
        ).fetchone()[0]

        notif_recoveries = conn.execute(
            "SELECT COUNT(*) FROM notifications WHERE ts > ? AND type='recovery'",
            (cutoff,),
        ).fetchone()[0]

        most_failed_row = conn.execute(
            "SELECT provider FROM health_snapshots WHERE ts > ? AND status != 'healthy' "
            "GROUP BY provider ORDER BY COUNT(*) DESC LIMIT 1",
            (cutoff,),
        ).fetchone()
        most_failed = most_failed_row[0] if most_failed_row else "none"

        conn.close()

        output = {
            "window": f"{hours}h",
            "since": cutoff,
            "totalSnapshots": total,
            "currentStatus": current,
            "failuresByProvider": failures,
            "uptimeByProvider": rates,
            "mostFailedProvider": most_failed,
            "incidents": {
                "total": incident_total,
                "open": incident_open,
                "avgResolutionMins": incident_avg_mins,
            },
            "notifications": {
                "failures": notif_failures,
                "recoveries": notif_recoveries,
            },
        }
        print_json(output)

    else:
        error_exit("Usage: ops-db.py health <snapshot|latest|history|trends>")


# ── INCIDENTS ──

def cmd_incident(args):
    if len(args) < 1:
        error_exit("Usage: ops-db.py incident <open|close|list>")

    sub = args[0]

    if sub == "open":
        if len(args) < 2:
            error_exit("Usage: ops-db.py incident open <title>")
        title = args[1]
        opts = parse_args_after(args, 2)
        provider = opts.get("provider", "")
        severity = opts.get("severity", "medium")
        desc = opts.get("desc", "")

        result = sq_insert_return(
            "incidents",
            "INSERT INTO incidents (provider, severity, title, description) VALUES (?, ?, ?, ?)",
            (provider, severity, title, desc),
        )
        print_json(result)

    elif sub == "close":
        if len(args) < 2:
            error_exit("Usage: ops-db.py incident close <id>")
        try:
            incident_id = int(args[1])
        except ValueError:
            error_exit(f"Invalid incident id: {args[1]}")
        opts = parse_args_after(args, 2)
        resolution = opts.get("resolution", "")

        conn = get_conn()
        conn.execute(
            "UPDATE incidents SET closed_at=strftime('%Y-%m-%dT%H:%M:%SZ','now'), resolution=? WHERE id=?",
            (resolution, incident_id),
        )
        conn.commit()
        result = rows_to_json(conn.execute("SELECT * FROM incidents WHERE id=?", (incident_id,)).fetchall())
        conn.close()
        print_json(result)

    elif sub == "list":
        flag = args[1] if len(args) > 1 else "--open"
        if flag == "--all":
            print_json(sq("SELECT * FROM incidents ORDER BY opened_at DESC LIMIT 50"))
        else:
            print_json(sq("SELECT * FROM v_open_incidents"))

    else:
        error_exit("Usage: ops-db.py incident <open|close|list>")


# ── TASKS ──

def cmd_task(args):
    if len(args) < 1:
        error_exit("Usage: ops-db.py task <create|update|list|get>")

    sub = args[0]

    if sub == "create":
        if len(args) < 3:
            error_exit("Usage: ops-db.py task create <agent> <summary>")
        agent = args[1]
        task_summary = args[2]
        opts = parse_args_after(args, 3)
        urgency = opts.get("urgency", "routine")
        context = opts.get("context", "")
        files = opts.get("files", "")
        errors = opts.get("errors", "")
        outcome = opts.get("outcome", "")

        result = sq_insert_return(
            "tasks",
            "INSERT INTO tasks (agent, urgency, task, context, files, errors, outcome) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (agent, urgency, task_summary, context, files, errors, outcome),
        )
        print_json(result)

    elif sub == "update":
        if len(args) < 3:
            error_exit("Usage: ops-db.py task update <id> <status>")
        try:
            task_id = int(args[1])
        except ValueError:
            error_exit(f"Invalid task id: {args[1]}")
        status = args[2]
        opts = parse_args_after(args, 3)
        result_json = opts.get("result", "")

        conn = get_conn()
        conn.execute(
            "UPDATE tasks SET status=?, updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now'), result=? WHERE id=?",
            (status, result_json, task_id),
        )
        conn.commit()
        rows = rows_to_json(conn.execute("SELECT * FROM tasks WHERE id=?", (task_id,)).fetchall())
        conn.close()
        print_json(rows)

    elif sub == "list":
        opts = parse_args_after(args, 1)
        filter_status = opts.get("status", "")
        filter_agent = opts.get("agent", "")

        if not filter_status and not filter_agent:
            print_json(sq("SELECT * FROM v_pending_tasks"))
        else:
            conditions = []
            params = []
            if filter_status:
                conditions.append("status=?")
                params.append(filter_status)
            if filter_agent:
                conditions.append("agent=?")
                params.append(filter_agent)
            where = " AND ".join(conditions)
            print_json(sq(
                f"SELECT * FROM tasks WHERE {where} ORDER BY created_at DESC LIMIT 50",
                tuple(params),
            ))

    elif sub == "get":
        if len(args) < 2:
            error_exit("Usage: ops-db.py task get <id>")
        try:
            task_id = int(args[1])
        except ValueError:
            error_exit(f"Invalid task id: {args[1]}")
        print_json(sq("SELECT * FROM tasks WHERE id=?", (task_id,)))

    else:
        error_exit("Usage: ops-db.py task <create|update|list|get>")


# ── NOTIFICATIONS ──

def cmd_notify(args):
    if len(args) < 1:
        error_exit("Usage: ops-db.py notify <type> <provider> <message> | notify list | notify deliver <id>")

    sub = args[0]

    if sub == "list":
        rest = args[1:]
        flag = "--undelivered"
        limit = 20
        i = 0
        while i < len(rest):
            if rest[i] == "--undelivered":
                flag = "--undelivered"
                i += 1
            elif rest[i] == "--all":
                flag = "--all"
                i += 1
            elif rest[i] == "--limit" and i + 1 < len(rest):
                try:
                    limit = int(rest[i + 1])
                except ValueError:
                    error_exit(f"Invalid limit value: {rest[i + 1]}")
                i += 2
            else:
                i += 1

        if flag == "--all":
            print_json(sq("SELECT * FROM notifications ORDER BY ts DESC LIMIT ?", (limit,)))
        else:
            print_json(sq("SELECT * FROM v_undelivered_notifications LIMIT ?", (limit,)))

    elif sub == "deliver":
        if len(args) < 2:
            error_exit("Usage: ops-db.py notify deliver <id>")
        try:
            notif_id = int(args[1])
        except ValueError:
            error_exit(f"Invalid notification id: {args[1]}")
        sq_exec("UPDATE notifications SET delivered=1 WHERE id=?", (notif_id,))
        print_json({"status": "ok", "id": notif_id})

    else:
        # ops-db.py notify <type> <provider> <message> [--reason X]
        if len(args) < 3:
            error_exit("Usage: ops-db.py notify <type> <provider> <message>")
        ntype = args[0]
        provider = args[1]
        message = args[2]
        opts = parse_args_after(args, 3)
        reason = opts.get("reason", "")

        result = sq_insert_return(
            "notifications",
            "INSERT INTO notifications (type, provider, reason, message) VALUES (?, ?, ?, ?)",
            (ntype, provider, reason, message),
        )
        print_json(result)


# ── CONFIG ──

def cmd_config(args):
    if len(args) < 1:
        error_exit("Usage: ops-db.py config <log|recent>")

    sub = args[0]

    if sub == "log":
        if len(args) < 2:
            error_exit("Usage: ops-db.py config log '<json>'")
        try:
            line = json.loads(args[1])
        except (json.JSONDecodeError, ValueError) as e:
            error_exit(f"Invalid JSON: {e}")

        ts = line.get("ts", "")
        source = line.get("source", "")
        event = line.get("event", "")
        phash = line.get("previousHash", "")
        nhash = line.get("nextHash", "")
        pbytes = line.get("previousBytes")
        nbytes = line.get("nextBytes")
        gmode = line.get("gatewayModeAfter", "")
        susp = json.dumps(line.get("suspicious", []))
        result_val = line.get("result", "")

        sq_exec(
            "INSERT INTO config_changes (ts, source, event, previous_hash, next_hash, "
            "previous_bytes, next_bytes, gateway_mode, suspicious, result) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (ts, source, event, phash, nhash, pbytes, nbytes, gmode, susp, result_val),
        )
        print_json({"status": "ok", "ts": ts})

    elif sub == "recent":
        limit = 20
        if len(args) > 1 and args[1] == "--limit" and len(args) > 2:
            limit = int(args[2])
        print_json(sq("SELECT * FROM config_changes ORDER BY ts DESC LIMIT ?", (limit,)))

    else:
        error_exit("Usage: ops-db.py config <log|recent>")


# ── KV ──

def cmd_kv(args):
    if len(args) < 1:
        error_exit("Usage: ops-db.py kv <get|set>")

    sub = args[0]

    if sub == "get":
        if len(args) < 2:
            error_exit("Usage: ops-db.py kv get <key>")
        key = args[1]
        val = sq_exec_return_scalar("SELECT value FROM kv WHERE key=?", (key,))
        if val is not None:
            print_json({"key": key, "value": val})
        else:
            print_json({"key": key, "value": None})

    elif sub == "set":
        if len(args) < 3:
            error_exit("Usage: ops-db.py kv set <key> <value>")
        key = args[1]
        value = args[2]
        sq_exec(
            "INSERT OR REPLACE INTO kv (key, value, updated_at) "
            "VALUES (?, ?, strftime('%Y-%m-%dT%H:%M:%SZ','now'))",
            (key, value),
        )
        print_json({"status": "ok", "key": key})

    else:
        error_exit("Usage: ops-db.py kv <get|set>")


# ── RAW QUERY ──

def cmd_query(args):
    if len(args) < 1:
        error_exit("Usage: ops-db.py query '<SELECT ...>'")

    sql = args[0]
    # Safety: only allow SELECT
    if re.match(r'^\s*(insert|update|delete|drop|alter|create)', sql, re.IGNORECASE):
        print(json.dumps({"error": "Only SELECT queries allowed via query command"}), file=sys.stderr)
        sys.exit(1)

    print_json(sq(sql))


# ── STATS ──

def cmd_stats():
    tables = ["health_snapshots", "config_changes", "incidents", "tasks", "notifications", "kv"]
    conn = get_conn()
    result = {}
    for table in tables:
        count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        result[table] = count

    # DB size in KB
    try:
        size_bytes = os.path.getsize(DB_PATH)
        result["db_size_kb"] = size_bytes // 1024
    except OSError:
        result["db_size_kb"] = 0

    conn.close()
    print_json(result)


# ── INIT ──

def cmd_init():
    if os.path.isfile(INIT_SQL):
        with open(INIT_SQL, "r") as f:
            schema = f.read()
        conn = sqlite3.connect(DB_PATH)
        conn.execute("PRAGMA busy_timeout=5000")
        conn.executescript(schema)
        conn.close()
        print_json({"status": "ok", "message": "schema initialized"})
    else:
        error_exit(f"init SQL not found at {INIT_SQL}")


# ── MAIN ──

def main():
    if len(sys.argv) < 2:
        error_exit("Usage: ops-db.py <health|incident|task|notify|config|kv|query|stats|init>")

    auto_init()

    if not os.path.isfile(DB_PATH):
        error_exit(f"ops.db not found at {DB_PATH}")

    cmd = sys.argv[1]
    rest = sys.argv[2:]

    commands = {
        "health": lambda: cmd_health(rest),
        "incident": lambda: cmd_incident(rest),
        "task": lambda: cmd_task(rest),
        "notify": lambda: cmd_notify(rest),
        "config": lambda: cmd_config(rest),
        "kv": lambda: cmd_kv(rest),
        "query": lambda: cmd_query(rest),
        "stats": lambda: cmd_stats(),
        "init": lambda: cmd_init(),
    }

    handler = commands.get(cmd)
    if handler:
        handler()
    else:
        error_exit(f"Unknown command: {cmd}. Usage: ops-db.py <health|incident|task|notify|config|kv|query|stats|init>")


if __name__ == "__main__":
    main()
