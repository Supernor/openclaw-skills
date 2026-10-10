#!/usr/bin/env bash
# Run one bounded stability monitor at a time. The flock parent owns the lock
# until timeout has terminated the command process group, including descendants.
# Never reclaim a live lock by file mtime. Mtime does not track acquisition and
# killing only flock leaves its children running and permits overlapping checks.
# Restore pre-task bytes from backups/stability-monitor-cron.sh.preedit-4796.
set -uo pipefail
LOCK="/tmp/cron-stability-monitor.lock"
exec flock --close -n "$LOCK" timeout --signal=TERM --kill-after=10s 240s \
  /bin/bash -c '/root/.openclaw/scripts/startup-guard.sh 180 && /root/.openclaw/scripts/cron-wrapper.sh "stability-monitor" /root/.openclaw/scripts/stability-monitor.sh'
