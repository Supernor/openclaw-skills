#!/bin/bash
# === INTENT ===
# Thin wrapper (house rule: logic in python) -> deploy-verify.py: read-only check that the running artifact is the built artifact.
# Exit 0 all ok / 1 any fail; pass --alert (cron only) to post to Discord ops on state change. Output is one JSON object.
exec python3 /root/.openclaw/scripts/deploy-verify.py "$@"
