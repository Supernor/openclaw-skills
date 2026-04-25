#!/usr/bin/env bash
# bridge-audit.sh — Verify Bridge section activation wiring.
#
# WHEN TO USE: After adding/modifying any Bridge section. Before claiming "done."
# DON'T USE FOR: CSS/styling checks (use screenshots for that).
# IF ANY CHECK FAILS: The section is partially wired. Fix the missing point before deploying.
#   The FAIL message tells you exactly which file and what to add.
# VERIFY WITH: bridge-screenshots.sh <section> (visual proof after fixing)
#
# Checks 5 wiring points per section:
#   1. Nav button (index.html data-section)
#   2. Section container (index.html id="section-NAME")
#   3. Module allowlist (dashboard-api.py BRIDGE_DEFAULT_MODULES)
#   4. Screenshot coverage (bridge-screenshots.sh ALL_SECTIONS)
#   5. switchSection handler (app.js — explicit or SSE/on-demand)
#
# Usage:
#   bridge-audit.sh                    # audit all sections
#   bridge-audit.sh --section pipeline # audit one section
#   bridge-audit.sh --json             # machine-readable output

set -euo pipefail

BRIDGE_DIR="/root/bridge-dev"
SCRIPTS_DIR="/root/.openclaw/scripts"
INDEX="${BRIDGE_DIR}/index.html"
APPJS="${BRIDGE_DIR}/app.js"
API="${BRIDGE_DIR}/dashboard-api.py"
SCREENSHOTS="${SCRIPTS_DIR}/bridge-screenshots.sh"

PASS=0
FAIL=0
TOTAL=0
JSON_MODE=false
TARGET_SECTION=""
RESULTS=""

# Parse args
while [ $# -gt 0 ]; do
    case "$1" in
        --json) JSON_MODE=true; shift ;;
        --section) TARGET_SECTION="$2"; shift 2 ;;
        *) TARGET_SECTION="$1"; shift ;;
    esac
done

check() {
    local section="$1"
    local point="$2"
    local result="$3"
    local detail="$4"
    TOTAL=$((TOTAL + 1))
    if [ "$result" = "PASS" ]; then
        PASS=$((PASS + 1))
        $JSON_MODE || echo "  PASS: ${section}/${point}"
    else
        FAIL=$((FAIL + 1))
        if ! $JSON_MODE; then
            echo "  FAIL: ${section}/${point}"
            echo "    WHAT: ${point} missing for section '${section}'"
            echo "    WHY: ${detail}"
            echo "    DO THIS: See corrective action above"
            echo "    VERIFY: bridge-audit.sh --section ${section}"
        fi
    fi
    RESULTS="${RESULTS}{\"section\":\"${section}\",\"point\":\"${point}\",\"result\":\"${result}\",\"detail\":\"${detail}\"},"
}

audit_section() {
    local name="$1"
    $JSON_MODE || echo "--- ${name} ---"

    # 1. Nav button
    if grep -q "data-section=\"${name}\"" "$INDEX" 2>/dev/null; then
        check "$name" "nav_button" "PASS" ""
    else
        check "$name" "nav_button" "FAIL" "Add <button class=\"icon-btn\" data-section=\"${name}\" ...> to index.html nav bar (lines 85-157)"
    fi

    # 2. Section container
    if grep -q "id=\"section-${name}\"" "$INDEX" 2>/dev/null; then
        check "$name" "section_container" "PASS" ""
    else
        check "$name" "section_container" "FAIL" "Add <section class=\"section\" id=\"section-${name}\"> to index.html (lines 175-693)"
    fi

    # 3. Module allowlist
    if grep -q "\"${name}\"" "$API" 2>/dev/null && sed -n '/BRIDGE_DEFAULT_MODULES/,/\]/p' "$API" | grep -q "\"${name}\""; then
        check "$name" "module_allowlist" "PASS" ""
    else
        check "$name" "module_allowlist" "FAIL" "Add \"${name}\" to BRIDGE_DEFAULT_MODULES list in dashboard-api.py (line ~110)"
    fi

    # 4. Screenshot coverage
    if grep -q "${name}" "$SCREENSHOTS" 2>/dev/null && sed -n '/ALL_SECTIONS=/p' "$SCREENSHOTS" | grep -q "${name}"; then
        check "$name" "screenshot_coverage" "PASS" ""
    else
        check "$name" "screenshot_coverage" "FAIL" "Add '${name}' to ALL_SECTIONS in bridge-screenshots.sh (line ~32)"
    fi

    # 5. switchSection handler (check for name reference in switchSection context)
    # Health is default (no explicit handler needed). Others need name === "X" or equivalent.
    # Some sections use setup functions, pollers, or SSE — we check for ANY reference in the
    # switchSection block (lines 911-993) OR in skeleton/setup functions.
    # Static sections that need no data fetch: health (default), newidea (form), learn (static)
    if [ "$name" = "health" ] || [ "$name" = "newidea" ] || [ "$name" = "learn" ]; then
        check "$name" "switch_handler" "PASS" "default section"
    elif grep -qE "\"${name}\"|'${name}'" "$APPJS" 2>/dev/null && \
         grep -cE "(name === \"${name}\"|name === '${name}'|\"${name}\".*render|\"${name}\".*fetch|\"${name}\".*load|\"${name}\".*Skeleton|setup.*${name})" "$APPJS" 2>/dev/null | grep -qv '^0$'; then
        check "$name" "switch_handler" "PASS" ""
    else
        check "$name" "switch_handler" "FAIL" "Add 'else if (name === \"${name}\")' block in switchSection() in app.js (lines 911-993)"
    fi
}

# Get all sections from nav buttons
ALL_SECTIONS=$(grep -oP 'data-section="\K[^"]+' "$INDEX" | sort -u)

$JSON_MODE || echo "=== Bridge Activation Audit ==="
$JSON_MODE || echo ""

if [ -n "$TARGET_SECTION" ]; then
    audit_section "$TARGET_SECTION"
else
    for section in $ALL_SECTIONS; do
        audit_section "$section"
    done
fi

$JSON_MODE || echo ""
$JSON_MODE || echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"

if $JSON_MODE; then
    echo "{\"total\":${TOTAL},\"pass\":${PASS},\"fail\":${FAIL},\"sections\":[${RESULTS%,}]}"
fi

if [ "$FAIL" -gt 0 ]; then
    $JSON_MODE || echo "STATUS: FAIL — ${FAIL} wiring point(s) broken. Fix before deploying."
    exit 1
else
    $JSON_MODE || echo "STATUS: PASS — All sections fully wired."
    exit 0
fi
