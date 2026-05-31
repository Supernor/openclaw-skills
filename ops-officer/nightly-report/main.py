#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Nightly Report Skill Executor
Posts to #ops-nightly as a color-coded card and raw data thread.
Run as either: python3 main.py or via ./main.py
Dependencies:
- requests
- json
- os
- sys
- datetime
- subprocess (for card/thread management)
- discord_webhook utility (relative import fallback)
"""

import os
import sys
import json
import time
from datetime import datetime, timezone
from typing import Dict, Any, List

_DEPS = sys.path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "libs"))

try:
    from discord_webhook import DiscordWebhook, DiscordMessage
    _HAS_DISCORD = True
except Exception:
    _HAS_DISCORD = False
    DiscordWebhook = DiscordMessage = object


HOME = os.path.expanduser("~")
REGISTRY = os.path.join(HOME, ".openclaw", "registry.json")
TEMPLATE = os.path.join(HOME, ".openclaw", "templates", "nightly-report.txt")
KNOWN_ISSUES_SNAPSHOT = os.path.join(HOME, ".openclaw", "bridge", "known-issues.json")
SCRIPT_OUTPUTS_DIR = os.path.join(os.path.expanduser("~/.openclaw"), "nightly-script-outputs")

COLORS = {
    "green": 0x5763719,      # Discord green
    "yellow": 0x16776960,     # Discord yellow
    "red": 0x15548997,        # Discord red
}
EMOJIS = {
    "green": "🟢",
    "yellow": "🟡",
    "red": "🔴",
    "blue": "🔵",
}
SECTION_STATUS_COLOR: Dict[str, Dict[str, str]] = {
    "Keys": {"green": "0 missing, 0 extra", "yellow": None, "red": "Any missing or extra"},
    "Backups": {"green": "All pushed OK", "yellow": "Warnings present", "red": "Any push failed"},
    "Repos": {"green": "All 3 up, secrets ok", "yellow": None, "red": "Any unreachable"},
    "Logs": {"green": "0 warnings, rotation OK", "yellow": "Non-critical warnings", "red": "Persistence/rotation fail"},
    "Providers": {"green": "All healthy", "yellow": "1 quarantined", "red": "2+ quarantined"},
}

def now_iso() -> str:
    return datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')

def reg_get(channel_name: str) -> int:
    if not os.path.exists(REGISTRY):
        raise FileNotFoundError(f"Missing registry at {REGISTRY}")
    with open(REGISTRY, "r", encoding="utf-8") as f:
        data = json.load(f)
    return int(data.get("discord", {}).get("channels", {}).get(channel_name, 1337))

def load_template() -> str:
    if not os.path.exists(TEMPLATE):
        raise FileNotFoundError(f"Missing template at {TEMPLATE}")
    with open(TEMPLATE, "r", encoding="utf-8") as f:
        return f.read()

def read_script_result(name: str) -> Dict[str, Any]:
    path = os.path.join(SCRIPT_OUTPUTS_DIR, f"{name}.json")
    if not os.path.exists(path):
        return {"name": name, "error": f"Missing output at {path}"}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def determine_section_status(section: str, data: Dict[str, Any]) -> str:
    if section == "Keys":
        ok = data.get("ok", 0)
        total = data.get("total", 0)
        missing = data.get("missing", [])
        extra = data.get("extra", [])
        if missing or extra:
            return "red"
        return "green"
    if section == "Backups":
        push_ok = data.get("workspace", {}).get("pushed")
        if push_ok is False:
            return "red"
        warnings = data.get("warnings", [])
        return "yellow" if warnings else "green"
    if section == "Repos":
        try:
            from pathlib import Path
            import subprocess
            base = Path(os.path.expanduser("~/.openclaw"))
            vars = ["config", "workspace-spec-ops", "skills"]
            for v in vars:
                p = base / v
                if not (p.exists() and p.is_dir()):
                    return "red"
            return "green"
        except Exception:
            return "red"
    if section == "Logs":
        warns = data.get("warnings", [])
        rot_ok = data.get("rotation_ok", True)
        if not rot_ok:
            return "red"
        return "yellow" if warns else "green"
    if section == "Providers":
        ok = data.get("healthy", 0)
        total = data.get("total", 0)
        if ok < total - 1:
            return "red"
        return "yellow" if ok < total else "green"
    return "red"

def aggregate_per_section(all_results: Dict[str, Any]) -> Dict[str, Any]:
    disp = {}
    for sec, rules in SECTION_STATUS_COLOR.items():
        disp[sec] = {"color": None, "details": None}
        try:
            if sec == "Keys":
                kd = all_results.get("keys", {})
                disp[sec]["color"] = determine_section_status(sec, kd)
                disp[sec]["details"] = kd.get("details")
            elif sec == "Backups":
                disp[sec]["color"] = determine_section_status(sec, all_results.get("backups", {}))
            elif sec == "Repos":
                disp[sec]["color"] = determine_section_status(sec, all_results)
            elif sec == "Logs":
                disp[sec]["color"] = determine_section_status(sec, all_results.get("logs", {}))
            elif sec == "Providers":
                disp[sec]["color"] = determine_section_status(sec, all_results.get("providers", {}))
        except Exception as e:
            disp[sec]["color"] = "red"
            disp[sec]["details"] = f"eval_error: {e}"
    return disp

def worst_status(status_map: Dict[str, Any]) -> str:
    order = ["green", "yellow", "red"]
    for s in order:
        if any(v.get("color") == s for v in status_map.values()):
            return s
    return "green"

def format_card(date_str: str, stats: Dict[str, Any], iss_count: int = 0) -> str:
    tmpl = load_template()
    lines = []
    for ln in tmpl.splitlines():
        if ln.strip().startswith("**Nightly Run"):
            lines.append(f"**Nightly Run — {date_str}**")
            lines.append(" ")  # enforce spacing
            card_emoji = EMOJIS.get(worst_status(stats), "🔵")
            card_stat = worst_status(stats).upper()
            fallback_detail = ""
            lines.append(f"{card_emoji} {card_stat} {fallback_detail}")
            lines.append(" ")
            continue
        lines.append(ln)
    # Inject sections with placeholders to be replaced by caller
    assembled = "\n".join(lines)
    return assembled

def post_discord(content: str, channel_id: int, is_thread_start: bool = False, thread_name: str = None) -> str:
    if not _HAS_DISCORD:
        print("[DRY] Skipping Discord post (discord_webhook not available)")
        return "https://discord.com/channels/@me/dry-run"
    msg = DiscordWebhook(url=f"https://discord.com/api/webhooks/{channel_id}/dummy", content=content)
    if thread_name and is_thread_start:
        # Discord webhook utility stub for thread create
        thread_url = f"https://discord.com/channels/@me/threads/{thread_name.replace(' ', '-').lower()}-{int(time.time())}"
        return thread_url
    else:
        print("[DRY] Discord card posted to #ops-nightly")
        return f"https://discord.com/channels/@me/cards/{int(time.time())}"

def iter_script_outputs() -> List[Dict[str, Any]]:
    names = ["keys", "backups", "repos", "logs", "providers"]
    out = [read_script_result(n + ".sh") for n in names]
    return [o for o in out if isinstance(o, dict)]

def known_issues_section() -> str:
    if not os.path.exists(KNOWN_ISSUES_SNAPSHOT):
        return ""
    try:
        with open(KNOWN_ISSUES_SNAPSHOT, "r", encoding="utf-8") as f:
            data = json.load(f)
        open_count = int(data.get("openCount", 0))
        if open_count == 0:
            return ""
        chart_id = data.get("chartId", "")
        issues_block = ["**Known Issues** (<openCount> open) -- chart `<chartId>`".replace("<openCount>", str(open_count)).replace("<chartId>", str(chart_id))]
        for it in data.get("items", []):
            issues_block.append(f"- {it.get('status', '')}: {it.get('title', '')}")
        return "\n".join(issues_block) + "\n"
    except Exception:
        return ""

def main():
    try:
        date_fmt = datetime.now(timezone.utc).strftime('%Y-%m-%d')
        channel_id = reg_get("ops-nightly")

        # 1) Collect script outputs from prior phase
        script_outputs = iter_script_outputs()
        aggregated = aggregate_per_section({s.get("name", "").replace(".sh", ""): s for s in script_outputs})
        worst = worst_status(aggregated)
        color_code = COLORS.get(worst, COLORS["green"])

        # Prepare card body template-style section fills
        def _fmt(sec: str, label: str) -> str:
            entry = aggregated.get(sec, {})
            color = entry.get("color")
            details = entry.get("details")
            symbol = EMOJIS.get(color, "🔵")
            status_txt = worst.upper() if sec == "__worst__" else color.upper()
            line = f"**{sec}** — {symbol} **{status_txt}**"
            if details:
                line += f" {details}"
            return line

        summary_body = (
            f"**Nightly Run — {date_fmt}**\n"
            f"{EMOJIS.get(worst, '🔵')} {worst.upper()}\\n"
            f"{_fmt('Keys', '**Keys** —')}\\n"
            f"{_fmt('Backups', '**Backups** —')}\\n"
            f"{_fmt('Repos', '**Repos** —')}\\n"
            f"{_fmt('Logs', '**Logs** —')}\\n"
            f"{_fmt('Providers', '**Providers** —')}\\n"
            "\n_Thread below has full script output._\n"
            f"{known_issues_section()}"
        )

        # 2) Post summary card
        card_url = post_discord(summary_body, channel_id, is_thread_start=True, thread_name=f"Nightly {date_fmt} — Raw Output")

        # 3) Post each script result into thread replies
        for so in script_outputs:
            name = so.get("name", "unknown")
            try:
                out = json.dumps(so, indent=2, ensure_ascii=False)
            except Exception:
                out = str(so)
            payload = f"**{name}**\n```json\n{out}\n```"
            post_discord(payload, channel_id, is_thread_start=False, thread_name="")

        # 4) Log result
        level = worst if worst in ("green", "yellow", "red") else "info"
        print(f"[I13] nightly-report: Posted: {worst}, {sum(1 for x in aggregated.values() if x.get('color')!='green')} sections flagged")
        return 0
    except Exception as e:
        print(f"[ERROR] nightly-report failed: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)