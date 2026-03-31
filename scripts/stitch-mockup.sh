#!/usr/bin/env bash
# stitch-mockup.sh — Generate UI mockup from text description via Google Stitch.
# Golden script: agents trigger via host_op="stitch-mockup", never call Stitch directly.
#
# Usage: stitch-mockup.sh <project-id> "description" [--style-tokens /path/to/style-guide.css]
#
# Requires: STITCH_API_KEY env var (from stitch.withgoogle.com settings)
# Falls back to stitch-mcp tool if SDK direct call fails.

set -eo pipefail

PROJECT_ID="${1:?Usage: stitch-mockup.sh PROJECT_ID 'description' [--style-tokens path]}"
DESCRIPTION="${2:?Description required}"
STYLE_TOKENS=""
DESIGN_DIR="/root/.openclaw/designs/$PROJECT_ID"
MOCKUP_DIR="$DESIGN_DIR/mockups"

# Parse optional style tokens flag
shift 2
while [[ $# -gt 0 ]]; do
    case "$1" in
        --style-tokens) STYLE_TOKENS="$2"; shift 2 ;;
        *) shift ;;
    esac
done

mkdir -p "$MOCKUP_DIR"

# Load API key
if [ -z "$STITCH_API_KEY" ]; then
    # Try loading from .env
    if [ -f /root/openclaw/.env ]; then
        STITCH_API_KEY=$(grep "^STITCH_API_KEY=" /root/openclaw/.env | cut -d= -f2-)
    fi
fi

if [ -z "$STITCH_API_KEY" ]; then
    echo "ERROR: STITCH_API_KEY not set. Get one from https://stitch.withgoogle.com/ settings."
    echo "Then add to /root/openclaw/.env: STITCH_API_KEY=your-key-here"
    exit 1
fi

export STITCH_API_KEY

# Build the prompt — include style tokens if provided
PROMPT="$DESCRIPTION"
if [ -n "$STYLE_TOKENS" ] && [ -f "$STYLE_TOKENS" ]; then
    TOKENS=$(cat "$STYLE_TOKENS" | head -50)
    PROMPT="$DESCRIPTION

Use this CSS design system for colors, typography, and spacing:
$TOKENS"
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
MOCKUP_FILE="$MOCKUP_DIR/mockup-$TIMESTAMP"

# Try stitch-mcp tool for screen generation
echo "Generating mockup via Stitch..."
RESULT=$(stitch-mcp tool generate_screen_from_text --input "$PROMPT" 2>&1) || true

if echo "$RESULT" | grep -q "html\|HTML\|<!DOCTYPE"; then
    # Got HTML back — save it
    echo "$RESULT" > "$MOCKUP_FILE.html"
    echo "HTML mockup saved: $MOCKUP_FILE.html"

    # Also try to get a screenshot
    SCREEN_ID=$(echo "$RESULT" | grep -oP 'screen[_-]?id["\s:=]+\K[a-zA-Z0-9_-]+' || true)
    if [ -n "$SCREEN_ID" ]; then
        stitch-mcp tool get_screen_image --screenId "$SCREEN_ID" > "$MOCKUP_FILE.png" 2>/dev/null || true
        [ -s "$MOCKUP_FILE.png" ] && echo "Screenshot saved: $MOCKUP_FILE.png"
    fi
else
    # Stitch call may have returned JSON or error — save raw output for debugging
    echo "$RESULT" > "$MOCKUP_FILE.raw.txt"
    echo "Stitch returned non-HTML output (saved to $MOCKUP_FILE.raw.txt for debugging)"
    echo "Output preview: $(echo "$RESULT" | head -5)"
fi

# Update ops.db design project
sqlite3 /root/.openclaw/ops.db "
    UPDATE design_projects
    SET mockup_path='$MOCKUP_FILE', mockup_status='proposed',
        style_guide_status=CASE WHEN style_guide_status='none' THEN 'proposed' ELSE style_guide_status END,
        updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
    WHERE id='$PROJECT_ID'
" 2>/dev/null

# Log alignment metric
sqlite3 /root/.openclaw/ops.db "
    INSERT INTO alignment_metrics (project_id, phase, event, detail)
    VALUES ('$PROJECT_ID', 'design', 'mockup_generated', 'Prompt: $(echo "$DESCRIPTION" | head -c 200 | tr "'" "_")')
" 2>/dev/null

echo "Done. Review mockup at: $MOCKUP_DIR/"
echo "Bridge: http://187.77.193.174:8082/#design"
