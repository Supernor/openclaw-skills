#!/bin/bash
# === INTENT ===
# Reactor's inbound "webhook": exit (= wake orchestrator) the moment bb_messages grows.
B=$(sqlite3 /root/.openclaw/ops.db "SELECT COUNT(*) FROM bb_messages;")
for i in $(seq 1 360); do
  sleep 10
  N=$(sqlite3 /root/.openclaw/ops.db "SELECT COUNT(*) FROM bb_messages;")
  if [ "$N" != "$B" ]; then echo "NEW BACKBONE MAIL: $B -> $N (run bb-read --to robert)"; exit 0; fi
done
echo "no new mail in 60 min (heartbeat)"
