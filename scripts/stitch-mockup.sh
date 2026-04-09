#!/usr/bin/env bash
# Alignment: golden script for generating UI mockups via Google Stitch API.
# Role: take a project ID + text description, generate a visual mockup via Stitch SDK,
# save HTML + design system to project dir, optionally deploy preview to Cloudflare.
# Dependencies: @google/stitch-sdk, Eoin OAuth credentials at /root/.openclaw/gws-credentials/eoin/,
# design_projects table in ops.db, /root/.openclaw/designs/ for output, Cloudflare for preview.
# Key patterns: golden script boundary — agents MUST trigger via host_op="stitch-mockup",
# never call Stitch directly; on-demand only (per Tactyl principle: system arranges, never chooses).
# Usage: stitch-mockup.sh <project-id> "description" [--deploy-preview] [--device DESKTOP|MOBILE]
# Reference: /root/.openclaw/docs/policy-context-injection.md

set -eo pipefail

PROJECT_ID="${1:?Usage: stitch-mockup.sh PROJECT_ID 'description' [--deploy-preview] [--device TYPE]}"
DESCRIPTION="${2:?Description required}"
DEPLOY_PREVIEW=false
DEVICE="DESKTOP"
DESIGN_DIR="/root/projects/$PROJECT_ID"
MOCKUP_DIR="$DESIGN_DIR/mockups"

# Parse optional flags
shift 2
while [[ $# -gt 0 ]]; do
    case "$1" in
        --deploy-preview) DEPLOY_PREVIEW=true; shift ;;
        --device) DEVICE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

mkdir -p "$MOCKUP_DIR" "$DESIGN_DIR"

# Get OAuth access token from Eoin's credentials
ACCESS_TOKEN=$(python3 -c "
import json, urllib.request, urllib.parse
with open('/root/.openclaw/gws-credentials/eoin/credentials.json') as f:
    creds = json.load(f)
data = urllib.parse.urlencode({
    'client_id': creds['client_id'],
    'client_secret': creds['client_secret'],
    'refresh_token': creds['refresh_token'],
    'grant_type': 'refresh_token',
}).encode()
req = urllib.request.Request('https://oauth2.googleapis.com/token', data=data)
resp = urllib.request.urlopen(req)
print(json.loads(resp.read())['access_token'])
" 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
    echo "ERROR: Failed to get OAuth token from Eoin's credentials."
    echo "FIX: Re-auth Eoin with cloud-platform scope. See chart: blocked-stitch-api-key"
    exit 3  # permanent failure
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "Generating mockup via Stitch SDK..."

# Run Stitch via Node SDK
RESULT=$(STITCH_ACCESS_TOKEN="$ACCESS_TOKEN" GOOGLE_CLOUD_PROJECT="lead-generator-for-crs" node -e "
const { StitchToolClient } = require('/usr/lib/node_modules/@google/stitch-sdk');
const client = new StitchToolClient();

async function run() {
    // Create or reuse project
    let projectId;
    try {
        const projects = await client.callTool('list_projects', {});
        const existing = projects.projects ? projects.projects.find(p => p.title === '$PROJECT_ID') : null;
        if (existing) {
            projectId = existing.name.replace('projects/', '');
        }
    } catch(e) {}

    if (!projectId) {
        const proj = await client.callTool('create_project', { title: '$PROJECT_ID' });
        projectId = proj.name.replace('projects/', '');
    }

    // Generate screen
    const screen = await client.callTool('generate_screen_from_text', {
        projectId: projectId,
        prompt: \`$DESCRIPTION\`,
        deviceType: '$DEVICE'
    });

    // Output as JSON for bash to parse
    console.log(JSON.stringify({
        projectId: projectId,
        screen: screen,
        ok: true
    }));
}

run().catch(e => {
    console.log(JSON.stringify({ ok: false, error: e.message }));
    process.exit(1);
});
" 2>&1)

# Parse result
OK=$(echo "$RESULT" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print('true' if d.get('ok') else 'false')" 2>/dev/null || echo "false")

if [ "$OK" = "true" ]; then
    # Save the full result
    echo "$RESULT" > "$MOCKUP_DIR/stitch-$TIMESTAMP.json"
    echo "Stitch output saved: $MOCKUP_DIR/stitch-$TIMESTAMP.json"

    # Extract HTML if available
    echo "$RESULT" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
screen = data.get('screen', {})
# Try to find HTML content in the response
comps = screen.get('outputComponents', [])
for c in comps:
    s = c.get('screen', {})
    if s.get('htmlUri'):
        print(f'HTML URI: {s[\"htmlUri\"]}')
    ds = c.get('designSystem', {}).get('designSystem', {})
    if ds:
        print(f'Design System: {ds.get(\"displayName\",\"unnamed\")}')
        theme = ds.get('theme', {})
        print(f'Theme: {theme.get(\"colorMode\",\"?\")} / font={theme.get(\"bodyFont\",\"?\")} / color={theme.get(\"customColor\",\"?\")}')
        # Save design system markdown if present
        design_md = theme.get('designMd', '')
        if design_md:
            with open('$MOCKUP_DIR/design-system-$TIMESTAMP.md', 'w') as f:
                f.write(design_md)
            print(f'Design system saved: $MOCKUP_DIR/design-system-$TIMESTAMP.md')
" 2>/dev/null

    # Update ops.db
    sqlite3 /root/.openclaw/ops.db "
        UPDATE design_projects
        SET mockup_path='$MOCKUP_DIR/stitch-$TIMESTAMP.json', mockup_status='proposed',
            updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
        WHERE id='$PROJECT_ID'
    " 2>/dev/null

    # Deploy preview to Cloudflare if requested
    if [ "$DEPLOY_PREVIEW" = true ]; then
        echo "Deploying preview to Cloudflare Pages..."
        /root/.openclaw/scripts/deploy-preview.sh "$PROJECT_ID" 2>&1 || echo "Preview deploy failed (non-fatal)"
    fi

    echo "Done. Review: $MOCKUP_DIR/"
    echo "Bridge: http://187.77.193.174:8082/#design"
else
    ERROR=$(echo "$RESULT" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('error','unknown'))" 2>/dev/null || echo "$RESULT")
    echo "Stitch generation failed: $ERROR"
    echo "$RESULT" > "$MOCKUP_DIR/stitch-error-$TIMESTAMP.txt"
    exit 1
fi
