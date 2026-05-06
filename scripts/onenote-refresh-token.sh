#!/bin/bash
# Refreshes the OneNote access token and writes it to a plain file
# that the container can read. Run via cron every 30 min.
# Token cache (MSAL) handles the actual refresh logic.

TOKEN=$(python3 /root/.openclaw/scripts/onenote-auth.py --token 2>/dev/null)
if [ -n "$TOKEN" ]; then
    echo "$TOKEN" > /root/.openclaw/credentials/onenote-access-token
    chmod 644 /root/.openclaw/credentials/onenote-access-token
fi
