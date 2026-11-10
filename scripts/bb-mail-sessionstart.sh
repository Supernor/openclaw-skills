#!/bin/bash
# === INTENT ===
# SessionStart: make every new/cold session mail-aware and self-arming.
# T3 vs tmux Phase A (Robert 2026-11-08 11:08 PM): only MAIN Reactor arms the watcher; T3 task chats must not start it or run bb-read
# (one shared cursor + read receipts). A session is treated as a task chat ONLY when the role check exits 1 AND prints exactly "not-main";
# any other result (error, traceback, missing helper) = today's behaviour (watcher instruction shown).
/root/.openclaw/scripts/bb-mail-banner.sh
out=$(python3 -I /usr/local/lib/knownself-common/session_role.py --is-main 2>/dev/null); rc=$?
if [ "$rc" -eq 1 ] && [ "$out" = "not-main" ]; then
  echo "[backbone mail: this is a T3 task chat, not main Reactor. Do NOT start bb-mail-watch and do NOT run bb-read; main Reactor handles mail. Count above is informational.]"
else
  echo "[backbone mail watcher: start it now — Bash run_in_background: /root/.openclaw/scripts/bb-mail-watch.sh — so inbound MCP mail wakes this session without Robert prompting]"
fi
