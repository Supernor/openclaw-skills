#!/bin/bash
# === INTENT ===
# Thin wrapper (house rule: logic in python) -> vault-custody-check.py: read-only JSON custody check of Supernor/knownself-vault.
# Always exits 0; pass --alert (cron only) to post on state change. Output is one JSON object.
exec python3 /root/.openclaw/scripts/vault-custody-check.py "$@"
