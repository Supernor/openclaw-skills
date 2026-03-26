#!/bin/bash
# Pressure Relief System — tiered automated remediation for memory/CPU/disk pressure
# Called by stability-monitor.sh when thresholds are hit
# Tiers: 1=ELEVATED (free up easy stuff), 2=HIGH (defer work, prune harder), 3=CRITICAL (restart services)
#
# Usage: pressure-relief.sh <tier> [--dry-run] [--disk]
#   --disk: run disk-specific relief instead of memory relief
# Flag file: /root/.openclaw/pressure-mode — when present, agent-calling crons should defer

set -uo pipefail

TIER="${1:-1}"
MODE="memory"
DRY_RUN=""
shift || true
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN="--dry-run" ;;
    --disk) MODE="disk" ;;
  esac
done
PRESSURE_FLAG="/root/.openclaw/pressure-mode"
LOG="/root/.openclaw/logs/pressure-relief.log"
COOLDOWN_FILE="/root/.openclaw/.pressure-cooldown"
COOLDOWN_SECONDS=300  # 5 min between relief runs

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [TIER-$TIER] $1" >> "$LOG"; }
act() {
  if [ "$DRY_RUN" = "--dry-run" ]; then
    echo "[DRY-RUN] $1"
    log "DRY-RUN: $1"
  else
    log "ACTION: $1"
  fi
}

# Cooldown check — don't thrash relief every 5 min cron cycle
if [ -f "$COOLDOWN_FILE" ] && [ "$DRY_RUN" != "--dry-run" ]; then
  LAST_RUN=$(stat -c %Y "$COOLDOWN_FILE" 2>/dev/null) || LAST_RUN=0
  NOW=$(date +%s)
  ELAPSED=$(( NOW - LAST_RUN ))
  if [ "$ELAPSED" -lt "$COOLDOWN_SECONDS" ]; then
    log "SKIPPED: Cooldown active (${ELAPSED}s since last run, need ${COOLDOWN_SECONDS}s)"
    echo "Cooldown active — last relief was ${ELAPSED}s ago"
    exit 0
  fi
fi

mem_available_mb() {
  awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo
}

BEFORE=$(mem_available_mb)
log "=== Pressure relief TIER $TIER started === Available: ${BEFORE}MB"
FREED_DESC=""

# ─── MEMORY RELIEF (default mode) ───
if [ "$MODE" = "disk" ]; then
  # Skip memory tiers — jump to disk relief below
  BEFORE=$(mem_available_mb)
  true
elif [ "$TIER" -ge 1 ]; then
  # Drop kernel page cache, dentries, inodes
  act "Dropping kernel caches"
  if [ "$DRY_RUN" != "--dry-run" ]; then
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
  fi
  FREED_DESC="${FREED_DESC}caches "

  # Reap zombie processes (kill parent to clean up)
  ZOMBIE_PARENTS=$(ps -eo ppid,stat | awk '$2 ~ /Z/ {print $1}' | sort -u)
  if [ -n "$ZOMBIE_PARENTS" ]; then
    ZCOUNT=$(echo "$ZOMBIE_PARENTS" | wc -l)
    act "Reaping $ZCOUNT zombie parent(s)"
    if [ "$DRY_RUN" != "--dry-run" ]; then
      echo "$ZOMBIE_PARENTS" | while read -r ppid; do
        # Don't kill init or critical processes
        [ "$ppid" -le 1 ] && continue
        kill -SIGCHLD "$ppid" 2>/dev/null
      done
    fi
    FREED_DESC="${FREED_DESC}zombies "
  fi

  # Unload any Ollama models sitting in RAM
  LOADED_MODELS=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}')
  if [ -n "$LOADED_MODELS" ]; then
    act "Unloading Ollama models: $LOADED_MODELS"
    if [ "$DRY_RUN" != "--dry-run" ]; then
      echo "$LOADED_MODELS" | while read -r model; do
        ollama stop "$model" 2>/dev/null
      done
    fi
    FREED_DESC="${FREED_DESC}ollama "
  fi

  # Clear old temp files (>1 day)
  act "Clearing old /tmp files"
  if [ "$DRY_RUN" != "--dry-run" ]; then
    find /tmp -type f -mtime +1 -not -name 'code-*' -delete 2>/dev/null
  fi
  FREED_DESC="${FREED_DESC}tmp "
fi

# ─── TIER 2: HIGH (<300MB) — defer agent work, prune Docker ───
if [ "$MODE" = "memory" ] && [ "$TIER" -ge 2 ]; then
  # Enable pressure mode — agent-calling crons will check this and defer
  act "Enabling pressure mode flag"
  if [ "$DRY_RUN" != "--dry-run" ]; then
    echo "{\"tier\":$TIER,\"since\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"available_mb\":$BEFORE}" > "$PRESSURE_FLAG"
  fi
  FREED_DESC="${FREED_DESC}pressure-flag "

  # Docker: prune stopped containers and dangling images
  act "Docker prune (stopped containers + dangling images)"
  if [ "$DRY_RUN" != "--dry-run" ]; then
    docker container prune -f >/dev/null 2>&1
    docker image prune -f >/dev/null 2>&1
  fi
  FREED_DESC="${FREED_DESC}docker-prune "

  # Truncate large log files (>10MB) to last 1000 lines
  LARGE_LOGS=$(find /root/.openclaw/logs -name '*.log' -size +10M 2>/dev/null)
  if [ -n "$LARGE_LOGS" ]; then
    act "Truncating large logs"
    if [ "$DRY_RUN" != "--dry-run" ]; then
      echo "$LARGE_LOGS" | while read -r lf; do
        tail -1000 "$lf" > "${lf}.tmp" && mv "${lf}.tmp" "$lf"
      done
    fi
    FREED_DESC="${FREED_DESC}logs "
  fi

  # Docker build cache prune (keep last 5GB)
  act "Pruning Docker build cache (keep 5GB)"
  if [ "$DRY_RUN" != "--dry-run" ]; then
    docker builder prune -f --keep-storage 5g >/dev/null 2>&1
  fi
  FREED_DESC="${FREED_DESC}build-cache "
fi

# ─── TIER 3: CRITICAL (<200MB) — restart bloated services ───
if [ "$MODE" = "memory" ] && [ "$TIER" -ge 3 ]; then
  # Restart gateway if RSS > 500MB — WITH restart loop protection
  # Max 2 restarts per hour. After that, alert-only (no more restarts).
  RESTART_TRACKER="/root/.openclaw/.gw-restart-tracker"
  GW_RSS_KB=$(ps -o rss= -p $(pgrep -f "openclaw-gateway" | head -1) 2>/dev/null) || GW_RSS_KB=0
  GW_RSS_MB=$(( GW_RSS_KB / 1024 ))
  if [ "$GW_RSS_MB" -gt 500 ]; then
    # Count restarts in the last hour
    NOW=$(date +%s)
    HOUR_AGO=$((NOW - 3600))
    RESTART_COUNT=0
    if [ -f "$RESTART_TRACKER" ]; then
      # Each line is a unix timestamp of a restart
      RESTART_COUNT=$(awk -v cutoff="$HOUR_AGO" '$1 > cutoff' "$RESTART_TRACKER" | wc -l)
    fi

    if [ "$RESTART_COUNT" -ge 2 ]; then
      act "RESTART LOOP BLOCKED: Gateway RSS ${GW_RSS_MB}MB but already restarted ${RESTART_COUNT}x in last hour — skipping restart, alert only"
      log "LOOP-PROTECT: Blocked gateway restart ($RESTART_COUNT restarts in last hour). Manual intervention needed."
      FREED_DESC="${FREED_DESC}gw-restart-BLOCKED "
    else
      act "Restarting gateway (RSS: ${GW_RSS_MB}MB > 500MB threshold, ${RESTART_COUNT}/2 restarts this hour)"
      if [ "$DRY_RUN" != "--dry-run" ]; then
        echo "$NOW" >> "$RESTART_TRACKER"
        # Prune tracker entries older than 1 hour
        awk -v cutoff="$HOUR_AGO" '$1 > cutoff' "$RESTART_TRACKER" > "${RESTART_TRACKER}.tmp" && mv "${RESTART_TRACKER}.tmp" "$RESTART_TRACKER"
        cd /root/openclaw && docker compose restart openclaw-gateway >/dev/null 2>&1 &
      fi
      FREED_DESC="${FREED_DESC}gw-restart "
    fi
  fi

  # Kill stale VS Code server processes if they exist and are old (>24h)
  STALE_VSCODE=$(find /proc -maxdepth 1 -name '[0-9]*' -exec sh -c '
    p={}; pid=$(basename $p)
    cmdline=$(cat $p/cmdline 2>/dev/null | tr "\0" " ")
    if echo "$cmdline" | grep -q "vscode-server" 2>/dev/null; then
      start=$(stat -c %Y $p 2>/dev/null) || exit
      now=$(date +%s)
      age=$(( now - start ))
      if [ "$age" -gt 86400 ]; then echo "$pid"; fi
    fi
  ' \; 2>/dev/null)
  if [ -n "$STALE_VSCODE" ]; then
    VCOUNT=$(echo "$STALE_VSCODE" | wc -l)
    act "Found $VCOUNT stale VS Code processes (>24h old) — NOT killing (Robert may be connected)"
    log "INFO: Stale VS Code PIDs: $STALE_VSCODE"
    FREED_DESC="${FREED_DESC}vscode-flagged "
  fi
fi

# ─── DISK RELIEF (triggered with --disk flag) ───
if [ "$MODE" = "disk" ]; then
  DISK_BEFORE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
  DISK_FREE_GB=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
  log "=== Disk relief TIER $TIER started === ${DISK_BEFORE}% used, ${DISK_FREE_GB}GB free"

  # Disk Tier 1 (>75%): light cleanup
  if [ "$TIER" -ge 1 ]; then
    # Vacuum journald logs to 100MB
    act "Vacuuming journald to 100MB"
    if [ "$DRY_RUN" != "--dry-run" ]; then
      journalctl --vacuum-size=100M >/dev/null 2>&1
    fi
    FREED_DESC="${FREED_DESC}journal "

    # Clear old /tmp files (>3 days)
    act "Clearing /tmp files older than 3 days"
    if [ "$DRY_RUN" != "--dry-run" ]; then
      find /tmp -type f -mtime +3 -not -name 'code-*' -delete 2>/dev/null
    fi
    FREED_DESC="${FREED_DESC}tmp "

    # Truncate log files over 50MB to last 2000 lines
    LARGE_LOGS=$(find /root/.openclaw/logs /var/log -name '*.log' -size +50M 2>/dev/null)
    if [ -n "$LARGE_LOGS" ]; then
      act "Truncating logs over 50MB"
      if [ "$DRY_RUN" != "--dry-run" ]; then
        echo "$LARGE_LOGS" | while read -r lf; do
          tail -2000 "$lf" > "${lf}.tmp" && mv "${lf}.tmp" "$lf"
        done
      fi
      FREED_DESC="${FREED_DESC}logs "
    fi
  fi

  # Disk Tier 2 (>85%): Docker cleanup
  if [ "$TIER" -ge 2 ]; then
    # Prune stopped containers
    act "Docker: pruning stopped containers"
    if [ "$DRY_RUN" != "--dry-run" ]; then
      docker container prune -f >/dev/null 2>&1
    fi

    # Prune dangling images
    act "Docker: pruning dangling images"
    if [ "$DRY_RUN" != "--dry-run" ]; then
      docker image prune -f >/dev/null 2>&1
    fi

    # Prune build cache (keep 5GB)
    act "Docker: pruning build cache (keep 5GB)"
    if [ "$DRY_RUN" != "--dry-run" ]; then
      docker builder prune -f --keep-storage 5g >/dev/null 2>&1
    fi
    FREED_DESC="${FREED_DESC}docker-prune "

    # Remove old backup images (keep only openclaw:local)
    OLD_BACKUP_IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'backup|ghcr.io' | grep -v '<none>')
    if [ -n "$OLD_BACKUP_IMAGES" ]; then
      act "Docker: removing old backup/unused images: $OLD_BACKUP_IMAGES"
      if [ "$DRY_RUN" != "--dry-run" ]; then
        echo "$OLD_BACKUP_IMAGES" | while read -r img; do
          docker rmi "$img" >/dev/null 2>&1 || true
        done
      fi
      FREED_DESC="${FREED_DESC}old-images "
    fi
  fi

  # Disk Tier 3 (>90%): aggressive cleanup
  if [ "$TIER" -ge 3 ]; then
    # Remove ALL unused images (not just dangling)
    act "Docker: aggressive prune — removing all unused images"
    if [ "$DRY_RUN" != "--dry-run" ]; then
      docker image prune -a -f >/dev/null 2>&1
    fi

    # Flush entire build cache
    act "Docker: flushing entire build cache"
    if [ "$DRY_RUN" != "--dry-run" ]; then
      docker builder prune -a -f >/dev/null 2>&1
    fi
    FREED_DESC="${FREED_DESC}aggressive-prune "

    # Vacuum journald to 50MB
    act "Vacuuming journald to 50MB (aggressive)"
    if [ "$DRY_RUN" != "--dry-run" ]; then
      journalctl --vacuum-size=50M >/dev/null 2>&1
    fi
  fi

  if [ "$DRY_RUN" != "--dry-run" ]; then
    DISK_AFTER=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    DISK_FREE_AFTER=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    log "=== Disk relief complete === Before: ${DISK_BEFORE}% After: ${DISK_AFTER}% Free: ${DISK_FREE_GB}GB -> ${DISK_FREE_AFTER}GB Actions: ${FREED_DESC}"
    echo "Disk tier $TIER relief: ${DISK_BEFORE}% -> ${DISK_AFTER}% (${DISK_FREE_GB}GB -> ${DISK_FREE_AFTER}GB free). Actions: ${FREED_DESC}"
  else
    echo "Disk dry run complete. Would run: ${FREED_DESC}"
  fi
  exit 0
fi

# ─── Post-relief: measure memory results (memory mode only) ───
if [ "$MODE" = "memory" ]; then
  if [ "$DRY_RUN" != "--dry-run" ]; then
    touch "$COOLDOWN_FILE"
    AFTER=$(mem_available_mb)
    GAINED=$(( AFTER - BEFORE ))
    log "=== Relief complete === Before: ${BEFORE}MB After: ${AFTER}MB Gained: ${GAINED}MB Actions: ${FREED_DESC}"
    echo "Tier $TIER relief: ${BEFORE}MB -> ${AFTER}MB (+${GAINED}MB). Actions: ${FREED_DESC}"
  else
    echo "Dry run complete. Would run: ${FREED_DESC}"
  fi
fi

exit 0
