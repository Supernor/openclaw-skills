#!/usr/bin/env bash
# bridge-screenshots.sh — Multi-section, multi-viewport Bridge screenshots
# Uses Puppeteer for full-page capture via Chrome headless.
#
# Usage:
#   bridge-screenshots.sh health                     # 3 screenshots of health
#   bridge-screenshots.sh health activity             # 6 screenshots
#   bridge-screenshots.sh --all                       # all main sections
#
# Output: /tmp/bridge-screenshots/<section>-<device>-<date>.png
#
# Viewports (Robert's device research):
#   Mobile:  412x915  (Samsung Galaxy S26 Ultra)
#   Split:   720x900  (Windows split-screen)
#   Desktop: 1440x900 (Full desktop)
#
# For agents: dispatch via host_op=bridge-screenshots in ops.db task meta
# HTML: index.html search "AUTH PANEL"
# Chart: infra-bridge-screenshot-tool
# Added: 2026-04-23

set -eo pipefail

# Site name used for folder and filename prefix. Override with --site.
SITE_NAME="${SITE_NAME:-bridge}"
SITE_URL="${SITE_URL:-http://localhost:8082}"
BASE_DIR="/tmp/screenshots"
PUPPETEER_CORE="/root/.npm/_npx/7d92d9a2d2ccc630/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js"
TIMESTAMP=$(date -u +%Y-%m-%d-%H%M)
MAX_AGE_HOURS="${MAX_AGE_HOURS:-24}"  # Auto-prune screenshots older than this

ALL_SECTIONS="updates learn health ops activity newidea board design inspect workshop assembly feedback agents systemmap issues pipeline truth settings"

log() { echo "[$(date -u +%H:%M:%S)] $1"; }

# Parse args
SECTIONS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all)      SECTIONS="$ALL_SECTIONS"; shift ;;
    --site)     SITE_NAME="$2"; shift 2 ;;
    --url)      SITE_URL="$2"; shift 2 ;;
    --max-age)  MAX_AGE_HOURS="$2"; shift 2 ;;
    --recent)
      # Check if recent screenshots exist (within MAX_AGE_HOURS)
      SITE_DIR="${BASE_DIR}/${SITE_NAME}"
      if [ -d "$SITE_DIR" ]; then
        RECENT=$(find "$SITE_DIR" -name "*.png" -mmin -$((MAX_AGE_HOURS * 60)) 2>/dev/null | sort)
        if [ -n "$RECENT" ]; then
          echo "Recent screenshots (< ${MAX_AGE_HOURS}h old):"
          echo "$RECENT"
          exit 0
        fi
      fi
      echo "No recent screenshots found (threshold: ${MAX_AGE_HOURS}h)"
      exit 1
      ;;
    *)          SECTIONS="${SECTIONS} $1"; shift ;;
  esac
done

if [ -z "$SECTIONS" ]; then
  echo "Usage: bridge-screenshots.sh [--site NAME] [--url URL] [--max-age HOURS] <section...> | --all | --recent"
  echo "Sections: $ALL_SECTIONS"
  echo ""
  echo "Examples:"
  echo "  bridge-screenshots.sh health                    # Bridge health, 3 viewports"
  echo "  bridge-screenshots.sh --site lounge --url http://localhost:8084 health   # Lounge"
  echo "  bridge-screenshots.sh --recent                  # List screenshots < 24h old"
  echo "  bridge-screenshots.sh --max-age 2 --recent      # List screenshots < 2h old"
  exit 1
fi

# Site-specific output directory
OUTPUT_DIR="${BASE_DIR}/${SITE_NAME}"

mkdir -p "$OUTPUT_DIR"

# Write Puppeteer script — takes URL, width, height, output as args
SCRIPT=$(mktemp /tmp/bridge-ss-XXXX.mjs)
cat > "$SCRIPT" << PUPPEOF
import puppeteer from '${PUPPETEER_CORE}';
const [url, w, h, out] = process.argv.slice(2);
const browser = await puppeteer.launch({
  headless: true,
  executablePath: '/usr/bin/google-chrome-stable',
  args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'],
});
const page = await browser.newPage();
await page.setViewport({ width: parseInt(w), height: parseInt(h) });
await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 10000 });
// Wait for actual content to render — trigger-based, not timer.
// Watch for Bridge SSE to connect (green dot) or content to populate.
try {
  await page.waitForFunction(
    () => {
      const sseEl = document.querySelector('[data-state="connected"]');
      const cards = document.querySelectorAll('.provider-card, .auth-card, .agent-card');
      return sseEl || cards.length > 3;
    },
    { timeout: 10000 }
  );
} catch (e) {
  // If SSE doesn't connect in 10s, capture whatever rendered
}
// Bridge uses overflow:hidden on body — override to allow full-page capture
await page.evaluate(() => {
  document.body.style.overflow = 'visible';
  document.body.style.height = 'auto';
  document.documentElement.style.overflow = 'visible';
  document.documentElement.style.height = 'auto';
  const main = document.getElementById('main');
  if (main) { main.style.overflow = 'visible'; main.style.height = 'auto'; main.style.maxHeight = 'none'; }
});
await page.screenshot({ path: out, fullPage: true });
await browser.close();
console.log('OK: ' + out);
PUPPEOF

VIEWPORTS="412:915:mobile 720:900:split 1440:900:desktop"
TOTAL=0
CAPTURED=0
FAILED=0
FILES=""

# Auto-prune old screenshots before capturing new ones
# Why: /tmp fills up over time. Keep only recent screenshots.
if [ -d "$OUTPUT_DIR" ]; then
  PRUNED=$(find "$OUTPUT_DIR" -name "*.png" -mmin +$((MAX_AGE_HOURS * 60)) -delete -print 2>/dev/null | wc -l)
  [ "$PRUNED" -gt 0 ] && log "Pruned ${PRUNED} screenshots older than ${MAX_AGE_HOURS}h"
fi

for section in $SECTIONS; do
  for vp in $VIEWPORTS; do
    IFS=: read -r width height device <<< "$vp"
    TOTAL=$((TOTAL + 1))
    url="${SITE_URL}/#${section}"
    # Filename: site-section-widthpx-device-YYYY-MM-DD-HHMM.png
    # Why: date+time lets agents check if "recent enough" without re-capturing
    # Width in filename so you can tell viewport at a glance
    filename="${SITE_NAME}-${section}-${width}px-${device}-${TIMESTAMP}.png"
    filepath="${OUTPUT_DIR}/${filename}"

    log "Capturing ${section} @ ${device} (${width}x${height})..."

    if timeout 20 node "$SCRIPT" "$url" "$width" "$height" "$filepath" 2>/dev/null; then
      if [ -f "$filepath" ] && [ -s "$filepath" ]; then
        SIZE=$(du -h "$filepath" | cut -f1)
        log "  OK: ${filename} (${SIZE})"
        CAPTURED=$((CAPTURED + 1))
        FILES="${FILES} ${filepath}"
      else
        log "  FAILED: empty file"
        FAILED=$((FAILED + 1))
      fi
    else
      log "  FAILED: timeout or error"
      FAILED=$((FAILED + 1))
    fi
  done
done

rm -f "$SCRIPT"

log ""
log "Done: ${CAPTURED}/${TOTAL} captured, ${FAILED} failed"
log "Screenshots: ${OUTPUT_DIR}/"

# JSON summary for agent consumption
echo ""
echo '{"total":'$TOTAL',"captured":'$CAPTURED',"failed":'$FAILED',"dir":"'$OUTPUT_DIR'","files":['
first=true
for f in $FILES; do
  $first || echo -n ","
  first=false
  echo -n '"'$f'"'
done
echo ']}'
