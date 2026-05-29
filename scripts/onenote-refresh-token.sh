#!/bin/bash
# Refreshes the OneNote access token and writes it to a plain file
# that the container can read. Run via cron every 30 min.
# Token cache (MSAL) handles the actual refresh logic.
#
# Logging: stderr from onenote-auth.py is redirected to LOG (was 2>/dev/null,
# which silenced MSAL/Azure errors and let the access-token go stale invisibly).
# See chart issue-onenote-refresh-silent-fail-20260528.

LOG=/root/.openclaw/logs/onenote-refresh-token.log
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "[$TS] refresh attempt" >> "$LOG"
TOKEN=$(python3 /root/.openclaw/scripts/onenote-auth.py --token 2>>"$LOG")
if [ -n "$TOKEN" ]; then
    echo "$TOKEN" > /root/.openclaw/credentials/onenote-access-token
    chmod 644 /root/.openclaw/credentials/onenote-access-token
    echo "[$TS] refresh OK (token len=${#TOKEN})" >> "$LOG"
else
    echo "[$TS] refresh FAILED (empty token - see stderr above)" >> "$LOG"
    exit 1
fi
