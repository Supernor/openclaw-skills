#!/usr/bin/env bash
# lint-error-quality.sh — Check that key scripts follow the Error Quality SOP.
#
# WHEN TO USE: Before deploying changes to operational scripts.
# DON'T USE FOR: Application code inside the OpenClaw container.
# IF ANY CHECK FAILS: Add educational context to the flagged error paths.
#   See /root/.openclaw/docs/error-quality-sop.md for the required format.
# VERIFY: lint-error-quality.sh (must exit 0)

set -uo pipefail
# NOTE: no -e because grep returns 1 on no match, which is expected in checks

SCRIPTS_DIR="/root/.openclaw/scripts"
PASS=0
FAIL=0
WARNINGS=0

# Key scripts that MUST have educational errors
KEY_SCRIPTS=(
    "deferred-executor.py"
    "host-ops-executor.py"
    "truth-gate.py"
    "bearings.py"
    "bearings-response-handler.py"
    "boy-scout-triage.py"
    "nightly-dispatch.py"
    "workshop-submit.sh"
    "codex-auth-watcher.sh"
    "fix-codex-auth.sh"
    "bridge-audit.sh"
    "opsdb.py"
)

check_script() {
    local script="$1"
    local filepath="${SCRIPTS_DIR}/${script}"
    local issues=0

    if [ ! -f "$filepath" ]; then
        echo "  SKIP: $script (not found)"
        return
    fi

    # Check 1: Script header has guidance (WHEN TO USE or Usage or NOTE FOR AGENTS)
    if grep -qiE "WHEN TO USE|Usage:|NOTE FOR AGENTS|DON.T USE FOR" "$filepath"; then
        PASS=$((PASS + 1))
    else
        echo "  WARN: $script — missing header guidance (WHEN TO USE / Usage / NOTE FOR AGENTS)"
        WARNINGS=$((WARNINGS + 1))
        issues=$((issues + 1))
    fi

    # Check 2: For Python scripts, check bare except blocks without educational context
    if [[ "$script" == *.py ]]; then
        # Count bare 'except Exception' or 'except:' that just pass/log without guidance
        bare_excepts=$(grep -c "except.*:" "$filepath" 2>/dev/null || echo 0)
        guided_excepts=$(grep -c "except.*:" "$filepath" 2>/dev/null | head -1)
        # Check for at least one educational error pattern in the file
        if grep -qiE "DO THIS|VERIFY|WHY:|USE THIS INSTEAD|educational|corrective" "$filepath"; then
            PASS=$((PASS + 1))
        else
            if [ "$bare_excepts" -gt 3 ]; then
                echo "  WARN: $script — $bare_excepts exception handlers but no educational error patterns found"
                WARNINGS=$((WARNINGS + 1))
                issues=$((issues + 1))
            else
                PASS=$((PASS + 1))
            fi
        fi
    fi

    # Check 3: For shell scripts, check exit 1 without preceding error message
    if [[ "$script" == *.sh ]]; then
        # Look for 'exit 1' not preceded by echo/log/printf on the previous line
        bare_exits=$(grep -n "exit 1" "$filepath" 2>/dev/null | while read -r line; do
            lineno=$(echo "$line" | cut -d: -f1)
            prev=$((lineno - 1))
            if ! sed -n "${prev}p" "$filepath" | grep -qiE "echo\|log\|printf\|ERROR\|FAIL"; then
                echo "$lineno"
            fi
        done | wc -l)
        if [ "$bare_exits" -gt 0 ]; then
            echo "  WARN: $script — $bare_exits exit(1) without preceding error message"
            WARNINGS=$((WARNINGS + 1))
            issues=$((issues + 1))
        else
            PASS=$((PASS + 1))
        fi
    fi

    # Check 4: Script has at least one corrective action pattern
    if grep -qiE "DO THIS|USE THIS|VERIFY WITH|FIX:|SAFE FALLBACK" "$filepath"; then
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $script — no corrective action guidance found (needs DO THIS / VERIFY WITH / FIX)"
        FAIL=$((FAIL + 1))
        issues=$((issues + 1))
    fi

    if [ "$issues" -eq 0 ]; then
        echo "  PASS: $script"
    fi
}

echo "=== Error Quality Lint ==="
echo ""

for script in "${KEY_SCRIPTS[@]}"; do
    check_script "$script"
done

echo ""
echo "Results: $PASS passed, $FAIL failed, $WARNINGS warnings"

if [ "$FAIL" -gt 0 ]; then
    echo "STATUS: FAIL — $FAIL script(s) missing required error guidance."
    echo "DO THIS: Add ERROR/WHY/DO THIS/VERIFY patterns. See /root/.openclaw/docs/error-quality-sop.md"
    exit 1
else
    echo "STATUS: PASS — All key scripts have educational error guidance."
    exit 0
fi
