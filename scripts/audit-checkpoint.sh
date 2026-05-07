#!/bin/bash
# audit-checkpoint — Timestamped backup of ops.db + config before mutations
#
# Usage:
#   audit-checkpoint.sh create [label]   # Create checkpoint
#   audit-checkpoint.sh restore <dir>    # Restore from checkpoint
#   audit-checkpoint.sh list             # List checkpoints
#   audit-checkpoint.sh verify <dir>     # Verify checkpoint is restorable
#
# Creates: /root/.openclaw/checkpoints/<timestamp>-<label>/
#   ops.db, ops.db-wal, ops.db-shm, openclaw.json, before-counts.json

set -euo pipefail

CHECKPOINT_DIR="/root/.openclaw/checkpoints"
OPS_DB="/root/.openclaw/ops.db"
CONFIG="/root/.openclaw/openclaw.json"

mkdir -p "$CHECKPOINT_DIR"

cmd="${1:-help}"
shift || true

case "$cmd" in
    create)
        LABEL="${1:-manual}"
        TS=$(date -u +%Y%m%dT%H%M%SZ)
        DIR="$CHECKPOINT_DIR/${TS}-${LABEL}"
        mkdir -p "$DIR"

        # Backup ops.db (with WAL checkpoint first for consistency)
        sqlite3 "$OPS_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
        cp "$OPS_DB" "$DIR/ops.db"
        cp "${OPS_DB}-wal" "$DIR/ops.db-wal" 2>/dev/null || true
        cp "${OPS_DB}-shm" "$DIR/ops.db-shm" 2>/dev/null || true

        # Backup config
        cp "$CONFIG" "$DIR/openclaw.json"

        # Record before-counts
        sqlite3 "$OPS_DB" "
            SELECT json_object(
                'tasks_total', (SELECT COUNT(*) FROM tasks),
                'tasks_completed', (SELECT COUNT(*) FROM tasks WHERE status='completed'),
                'tasks_cancelled', (SELECT COUNT(*) FROM tasks WHERE status='cancelled'),
                'tasks_blocked', (SELECT COUNT(*) FROM tasks WHERE status='blocked'),
                'tasks_pending', (SELECT COUNT(*) FROM tasks WHERE status='pending'),
                'tasks_archive', (SELECT COUNT(*) FROM tasks_archive),
                'intents', (SELECT COUNT(*) FROM intents),
                'engine_usage', (SELECT COUNT(*) FROM engine_usage),
                'bearings_pending', (SELECT COUNT(*) FROM bearings_queue WHERE status='pending'),
                'cron_outcomes', (SELECT COUNT(*) FROM cron_outcomes),
                'charts', (SELECT COUNT(*) FROM charts_mirror),
                'journal_mode', (SELECT * FROM pragma_journal_mode),
                'timestamp', '$TS',
                'label', '$LABEL'
            );
        " > "$DIR/before-counts.json"

        echo "Checkpoint created: $DIR"
        cat "$DIR/before-counts.json" | python3 -m json.tool 2>/dev/null || cat "$DIR/before-counts.json"
        ;;

    restore)
        DIR="${1:?checkpoint directory required}"
        if [ ! -f "$DIR/ops.db" ]; then
            echo "Error: No ops.db in $DIR" >&2
            exit 1
        fi

        # Stop executor to prevent writes during restore
        echo "WARNING: Restoring from $DIR"
        echo "This will overwrite ops.db and openclaw.json"

        # Checkpoint current WAL
        sqlite3 "$OPS_DB" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true

        # Restore
        cp "$DIR/ops.db" "$OPS_DB"
        cp "$DIR/ops.db-wal" "${OPS_DB}-wal" 2>/dev/null || true
        cp "$DIR/ops.db-shm" "${OPS_DB}-shm" 2>/dev/null || true
        cp "$DIR/openclaw.json" "$CONFIG"

        echo "Restored from: $DIR"
        echo "Before-counts from checkpoint:"
        cat "$DIR/before-counts.json" | python3 -m json.tool 2>/dev/null || cat "$DIR/before-counts.json"
        echo ""
        echo "Current counts:"
        sqlite3 "$OPS_DB" "SELECT 'tasks=' || COUNT(*) FROM tasks; SELECT 'archive=' || COUNT(*) FROM tasks_archive;"
        ;;

    list)
        if [ -d "$CHECKPOINT_DIR" ]; then
            for d in "$CHECKPOINT_DIR"/*/; do
                [ -d "$d" ] || continue
                name=$(basename "$d")
                size=$(du -sh "$d" 2>/dev/null | cut -f1)
                echo "$name  ($size)"
            done
        else
            echo "No checkpoints found."
        fi
        ;;

    verify)
        DIR="${1:?checkpoint directory required}"
        ERRORS=0
        for f in ops.db openclaw.json before-counts.json; do
            if [ -f "$DIR/$f" ]; then
                echo "OK: $f exists ($(stat -c%s "$DIR/$f") bytes)"
            else
                echo "MISSING: $f"
                ERRORS=$((ERRORS + 1))
            fi
        done
        # Verify db is readable
        if sqlite3 "$DIR/ops.db" "SELECT COUNT(*) FROM tasks;" >/dev/null 2>&1; then
            echo "OK: ops.db is readable"
        else
            echo "FAIL: ops.db is corrupt"
            ERRORS=$((ERRORS + 1))
        fi
        if [ $ERRORS -eq 0 ]; then
            echo "Checkpoint verified: $DIR"
        else
            echo "FAIL: $ERRORS errors found"
            exit 1
        fi
        ;;

    help|*)
        echo "audit-checkpoint — Backup/restore for automation audit"
        echo ""
        echo "Usage: audit-checkpoint.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  create [label]    Create timestamped checkpoint"
        echo "                    Example: audit-checkpoint.sh create pre-telemetry-fix"
        echo "  restore <dir>     Restore ops.db + config from checkpoint"
        echo "                    Example: audit-checkpoint.sh restore /root/.openclaw/checkpoints/20260506T191231Z-pre-audit"
        echo "  list              List all checkpoints with sizes"
        echo "  verify <dir>      Verify checkpoint files exist and db is readable"
        echo ""
        echo "Checkpoints saved to: /root/.openclaw/checkpoints/"
        echo "Each checkpoint contains: ops.db, openclaw.json, before-counts.json"
        echo ""
        echo "COMMON MISTAKES:"
        echo "  - Forgetting to create a checkpoint before mutations → always 'create' first"
        echo "  - Using 'restore' without stopping the executor → data may be overwritten"
        echo "  - Missing the label → use descriptive labels like 'pre-wal-change'"
        ;;
esac
