#!/usr/bin/env bash
# infrastructure-audit.sh — Audit scripts, crons, tables, services.
# Golden script: runs on host where all paths are accessible.
# Reports what exists vs what's charted.
#
# Usage: infrastructure-audit.sh [scripts|crons|tables|services|all]

set -eo pipefail
trap '' PIPE  # Ignore SIGPIPE — systemctl and sqlite3 pipes can break early

CHART="/usr/local/bin/chart"
OPS_DB="/root/.openclaw/ops.db"

audit_scripts() {
    echo "=== SCRIPTS AUDIT ==="
    echo "Directory: /root/.openclaw/scripts/"
    TOTAL=$(ls /root/.openclaw/scripts/*.sh /root/.openclaw/scripts/*.py 2>/dev/null | wc -l)
    echo "Total: $TOTAL"
    echo ""
    echo "Top 25 scripts (by recent modification):"
    ls -t /root/.openclaw/scripts/*.sh /root/.openclaw/scripts/*.py 2>/dev/null | head -25 | while read FILE; do
        NAME=$(basename "$FILE")
        DESC=$(head -3 "$FILE" 2>/dev/null | grep -oP '(?<=# |""").*' | head -1 | cut -c1-60)
        echo "  $NAME — $DESC"
    done
}

audit_crons() {
    echo "=== CRONS AUDIT ==="
    TOTAL=$(crontab -l 2>/dev/null | grep -v "^#\|^$" | wc -l)
    echo "Total cron entries: $TOTAL"
    echo ""
    crontab -l 2>/dev/null | grep -v "^#\|^$" | while read line; do
        SCRIPT=$(echo "$line" | grep -oP '/root/[^\s]+' | head -1)
        NAME=$(basename "$SCRIPT" 2>/dev/null | sed 's/\.\(sh\|py\)$//' 2>/dev/null)
        SCHEDULE=$(echo "$line" | awk '{print $1,$2,$3,$4,$5}')
        [ -n "$NAME" ] && echo "  $SCHEDULE — $NAME"
    done
}

audit_tables() {
    echo "=== OPS.DB TABLES AUDIT ==="
    # List tables with row counts — skip per-item chart search (too slow via LanceDB)
    sqlite3 "$OPS_DB" "
        SELECT m.name,
               (SELECT COUNT(*) FROM pragma_table_info(m.name)) as cols
        FROM sqlite_master m WHERE m.type='table' AND m.name NOT LIKE 'sqlite_%'
        ORDER BY m.name
    " 2>/dev/null | while IFS='|' read TABLE COLS; do
        COUNT=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null || echo "?")
        echo "  $TABLE ($COUNT rows, $COLS cols)"
    done
}

audit_services() {
    echo "=== SYSTEMD SERVICES AUDIT ==="
    systemctl list-units 'openclaw-*' --no-pager 2>/dev/null | grep "\.service" | grep "loaded" | while read line; do
        SVC=$(echo "$line" | awk '{print $1}')
        STATE=$(echo "$line" | awk '{print $3, $4}')
        echo "  $SVC — $STATE"
    done || true
}

case "${1:-all}" in
    scripts)  audit_scripts ;;
    crons)    audit_crons ;;
    tables)   audit_tables ;;
    services) audit_services ;;
    all)      audit_scripts; echo ""; audit_crons; echo ""; audit_tables; echo ""; audit_services ;;
    *)        echo "Usage: infrastructure-audit.sh [scripts|crons|tables|services|all]" ;;
esac
