#!/bin/bash
# earlyoom-notify.sh - Telegram alert when earlyoom kills a runaway process.
#
# WHY: earlyoom only acts in a true memory emergency (RAM AND swap both under
# the configured threshold). When it does, Robert must be told WHAT got killed
# and WHY - this is the resilience net firing, not a crash. Delivery is via the
# Telegram Bot API directly (bypasses the OpenClaw gateway) because the whole
# point is to alert even when the box is under the memory pressure that could
# take the gateway down with it.
#
# Invoked by earlyoom via its -N flag. earlyoom sets EARLYOOM_NAME / EARLYOOM_PID
# for the victim process. Created 2026-05-27 (resilience hardening).

TOKEN=$(grep '^TELEGRAM_BOT_TOKEN_ROBERT=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
[ -z "$TOKEN" ] && TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
TARGET=$(telegram-resolve robert 2>/dev/null)

NAME="${EARLYOOM_NAME:-unknown}"
PID="${EARLYOOM_PID:-?}"
MEM=$(free -m | awk '/Mem/{print $3"/"$2"MB used"}')
SWAP=$(free -m | awk '/Swap/{print $3"/"$2"MB used"}')

MSG="EARLYOOM ACTED (resilience net, NOT a crash)
Memory hit the danger threshold (RAM and swap both critically low), so to keep the server responsive instead of freezing, earlyoom killed the single biggest memory hog:
  process: ${NAME} (pid ${PID})
At time of kill: RAM ${MEM}, swap ${SWAP}.
The gateway is OOM-protected and should be unaffected. Check what ${NAME} was - if it was a build or a runaway, this is expected. If it was something important, that process needs a memory fix."

logger -t earlyoom-notify "killed ${NAME} pid ${PID}; RAM ${MEM} swap ${SWAP}"

if [ -n "$TOKEN" ] && [ -n "$TARGET" ]; then
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${TARGET}" -d text="${MSG}" >/dev/null 2>&1
fi
