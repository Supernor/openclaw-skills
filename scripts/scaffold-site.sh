#!/usr/bin/env bash
# scaffold-site.sh — Create a new website project from design artifacts.
# Called after design lock — the style guide is finalized, mockups approved.
#
# Usage: scaffold-site.sh <project-id> [stack]
#   stack: "static" (default) or "nextjs"
#
# Creates: /root/projects/<project-id>/ with locked style guide as base CSS.

set -eo pipefail

PROJECT_ID="${1:?Usage: scaffold-site.sh PROJECT_ID [static|nextjs]}"
STACK="${2:-static}"
PROJECT_DIR="/root/projects/$PROJECT_ID"
DESIGN_DIR="/root/.openclaw/designs/$PROJECT_ID"

if [ -d "$PROJECT_DIR" ]; then
    echo "Project directory already exists: $PROJECT_DIR"
    exit 1
fi

# Verify design is locked
STYLE_STATUS=$(sqlite3 /root/.openclaw/ops.db "SELECT style_guide_status FROM design_projects WHERE id='$PROJECT_ID'" 2>/dev/null)
if [ "$STYLE_STATUS" != "locked" ]; then
    echo "Design not locked yet (status: $STYLE_STATUS). Lock the design first."
    exit 1
fi

mkdir -p "$PROJECT_DIR/src" "$PROJECT_DIR/public"

if [ "$STACK" = "nextjs" ]; then
    cd "$PROJECT_DIR"
    npx create-next-app@latest . --typescript --tailwind --app --no-eslint --no-src-dir --import-alias "@/*" 2>&1 | tail -5
else
    # Static site scaffold
    cat > "$PROJECT_DIR/index.html" << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TITLE</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <!-- Components go here -->
  <script src="app.js"></script>
</body>
</html>
HTML
    touch "$PROJECT_DIR/app.js"
fi

# Copy locked style guide as base CSS
if [ -f "$DESIGN_DIR/locked-style-guide.css" ]; then
    cp "$DESIGN_DIR/locked-style-guide.css" "$PROJECT_DIR/style.css"
    echo "Copied locked style guide to project"
elif [ -f "$DESIGN_DIR/proposed-style-guide.css" ]; then
    cp "$DESIGN_DIR/proposed-style-guide.css" "$PROJECT_DIR/style.css"
    echo "Warning: Using proposed (not locked) style guide"
fi

# Init git
cd "$PROJECT_DIR"
git init
git add -A
git commit -m "Initial scaffold: $STACK site with locked style guide"

# Update ops.db
sqlite3 /root/.openclaw/ops.db "UPDATE design_projects SET deploy_status='none', updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id='$PROJECT_ID'" 2>/dev/null

echo "Scaffolded: $PROJECT_DIR ($STACK)"
echo "Next: deploy-preview.sh $PROJECT_ID"
