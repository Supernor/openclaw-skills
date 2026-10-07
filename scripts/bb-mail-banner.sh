#!/bin/bash
# === INTENT ===
# UserPromptSubmit hook: inject backbone unread count into every Reactor turn.
# Unread = bb_messages ids past the bb-read cursor. Silent when zero/error.
python3 - <<'PY' 2>/dev/null
import json, sqlite3
try:
    cur = 0
    try:
        d = json.load(open("/root/.openclaw/state/bb-read-cursor.json"))
        cur = max((v.get("last_id", 0) if isinstance(v, dict) else 0) for v in d.values()) if d else 0
    except Exception:
        pass
    con = sqlite3.connect("file:/root/.openclaw/ops.db?mode=ro", uri=True)
    n = con.execute("SELECT COUNT(*) FROM bb_messages WHERE id > ?", (cur,)).fetchone()[0]
    if n:
        print(f"[📬 backbone: {n} unread message(s) — run bb-read]")
except Exception:
    pass
PY
exit 0
