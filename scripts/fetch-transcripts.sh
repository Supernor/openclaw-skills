#!/usr/bin/env bash
# fetch-transcripts.sh — Use Gemini CLI to fetch YouTube transcripts and store in SQLite
# Processes videos in batches, extracts transcript + description + date
set -eo pipefail

DB="/root/.openclaw/transcripts.db"
OUTDIR="/tmp/transcripts"
mkdir -p "$OUTDIR"

# First 29 videos from @NateBJones flat playlist (newest first, ~1/day)
# Dates from Gemini's initial discovery + extrapolation
declare -A VIDEOS=(
  ["-_vL1KXd2rc"]="2026-03-07|GPT-5.4 Let Mickey Mouse Into a Production Database. Nobody Noticed."
  ["09sFAO7pklo"]="2026-03-06|Claude Code vs Codex: The Decision That Compounds Every Week You Delay"
  ["JYcidOS9ozU"]="2026-03-05|OpenAI Leaked GPT-5.4. It's a Distraction."
  ["O7SSQfiPDXA"]="2026-03-04|Everyone You Know Is About to Try Claude"
  ["pTtueIqrg0Q"]="2026-03-03|Dario Amodei Made One Mistake. Sam Altman Got $110 Billion."
  ["2JiMmye2ezg"]="2026-03-02|You Don't Need SaaS. The $0.10 System That Replaced My AI Workflow"
  ["RnjgLlQTMf0"]="2026-03-01|Why Every AI Skill You Learned 6 Months Ago Is Already Wrong"
  ["2ghhiPLg-jg"]="2026-02-28|My 10-Year-Old Vibe Codes. She Also Does Math by Hand."
  ["BpibZSMGtdY"]="2026-02-27|Prompting Just Split Into 4 Skills. You Only Know One."
  ["q6pbQ5li5Cg"]="2026-02-26|Don't Fall For the Stock Market Hype. The $7,000 Raise AI Is Giving You"
  ["0v9ixCWNhPo"]="2026-02-25|Three Labs Just Stole Claude's Brain. Here's What It Broke"
  ["QWzLPn164w0"]="2026-02-24|Prompt Engineering Is Dead. Context Engineering Is Dying."
  ["8jKAT8GNDE0"]="2026-02-23|Google's New AI Is Smarter Than Everyone's But It Costs HALF as Much."
  ["OMb5oTlC_q0"]="2026-02-22|Anthropic Tested 16 Models. Instructions Didn't Stop Them"
  ["O-0poNv2jD4"]="2026-02-21|The $285B Sell-Off Was Just the Beginning"
  ["-bQcWs1Z9a0"]="2026-02-20|$1,000 a Day in AI Costs. Three Engineers. No Writing Code."
  ["6r0UeMQE66I"]="2026-02-19|Why the Biggest AI Career Opportunity Just Appeared"
  ["bDcgHzCBgmQ"]="2026-02-18|The 5 Levels of AI Coding"
  ["5IzPLjqkFaE"]="2026-02-17|The OpenClaw Saga: Zuckerberg Begged This Developer to Join Meta."
  ["41UDGsBEjoI"]="2026-02-16|Codex 5.3 vs Opus 4.6: The Benchmark Nobody Expected."
  ["RtMLnCMv3do"]="2026-02-15|The Job Market Split Nobody's Talking About"
  ["NCgdpbEvNVA"]="2026-02-14|Why $650 Billion in AI Spending ISN'T Enough."
  ["U1oHRqUkI1E"]="2026-02-13|I Just Did a Full Day of Analyst Work in 10 Minutes."
  ["q-sClVMYY4w"]="2026-02-12|OpenClaw: 160,000 Developers Are Building Something OpenAI & Google Can't Stop."
  ["JKk77rzOL34"]="2026-02-11|Claude Opus 4.6: The Biggest AI Jump I've Covered"
  ["DGWtSzqCpog"]="2026-02-10|The $285 Billion Crash Wall Street Won't Explain Honestly."
  ["q6p-_W6_VoM"]="2026-02-09|Going Slower Feels Safer, But Your Domain Expertise Won't Save You"
  ["pSgy2P2q790"]="2026-02-08|Why the Smartest AI Teams Are Panic-Buying Compute"
  ["sLz4mAyykeE"]="2026-02-07|90% of People Fail at Vibe Coding. Here's the Actual Reason."
)

# Order for processing (newest first)
ORDER=(
  "-_vL1KXd2rc" "09sFAO7pklo" "JYcidOS9ozU" "O7SSQfiPDXA" "pTtueIqrg0Q"
  "2JiMmye2ezg" "RnjgLlQTMf0" "2ghhiPLg-jg" "BpibZSMGtdY" "q6pbQ5li5Cg"
  "0v9ixCWNhPo" "QWzLPn164w0" "8jKAT8GNDE0" "OMb5oTlC_q0" "O-0poNv2jD4"
  "-bQcWs1Z9a0" "6r0UeMQE66I" "bDcgHzCBgmQ" "5IzPLjqkFaE" "41UDGsBEjoI"
  "RtMLnCMv3do" "NCgdpbEvNVA" "U1oHRqUkI1E" "q-sClVMYY4w" "JKk77rzOL34"
  "DGWtSzqCpog" "q6p-_W6_VoM" "pSgy2P2q790" "sLz4mAyykeE"
)

fetch_transcript() {
  local vid="$1"
  local outfile="$OUTDIR/${vid}.txt"

  # Skip if already fetched
  if [ -f "$outfile" ] && [ -s "$outfile" ]; then
    echo "SKIP: $vid (already fetched)"
    return 0
  fi

  local url="https://www.youtube.com/watch?v=${vid}"
  echo "FETCH: $vid ..."

  # Use Gemini with no preamble injection to save tokens
  local result
  result=$(SKIP_PREAMBLE=1 timeout 180 gemini -p "Go to ${url} and extract:
1. The COMPLETE video transcript (every word spoken)
2. The video description
3. The exact upload date

Format your response EXACTLY as:
---DATE---
YYYY-MM-DD
---DESCRIPTION---
(full description text)
---TRANSCRIPT---
(complete transcript)
---END---

Do NOT summarize the transcript. Include every word." --output-format text --yolo 2>/dev/null) || true

  if [ -n "$result" ]; then
    echo "$result" > "$outfile"
    echo "OK: $vid ($(wc -c < "$outfile") bytes)"
  else
    echo "FAIL: $vid"
  fi
}

insert_to_db() {
  local vid="$1"
  local file="$OUTDIR/${vid}.txt"
  local meta="${VIDEOS[$vid]}"
  local est_date="${meta%%|*}"
  local short_title="${meta#*|}"

  if [ ! -f "$file" ] || [ ! -s "$file" ]; then
    echo "NO DATA: $vid"
    return 1
  fi

  local content
  content=$(cat "$file")

  # Extract sections
  local date_found description transcript
  date_found=$(echo "$content" | sed -n '/---DATE---/,/---DESCRIPTION---/p' | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
  description=$(echo "$content" | sed -n '/---DESCRIPTION---/,/---TRANSCRIPT---/p' | sed '1d;$d')
  transcript=$(echo "$content" | sed -n '/---TRANSCRIPT---/,/---END---/p' | sed '1d;$d')

  # Use Gemini date if found, else estimated
  local final_date="${date_found:-$est_date}"

  # Get full title from flat playlist data
  local full_title
  full_title=$(grep "^${vid}|" /tmp/natebjones-videos.txt 2>/dev/null | cut -d'|' -f2) || true
  full_title="${full_title:-$short_title}"

  if [ -z "$transcript" ]; then
    # If structured extraction failed, use entire content as transcript
    transcript="$content"
    description=""
  fi

  # Insert into SQLite (escape single quotes)
  local url="https://www.youtube.com/watch?v=${vid}"
  python3 << PYEOF
import sqlite3, sys
db = sqlite3.connect("$DB")
try:
    db.execute("""INSERT OR REPLACE INTO videos
        (video_id, title, publish_date, url, description, transcript, source, trust_level, trusted_by, channel)
        VALUES (?, ?, ?, ?, ?, ?, 'external', 0.9, 'Robert', '@NateBJones')""",
        ("""$vid""",
         db.execute("SELECT 1").fetchone() and """${full_title//\"/\\\"}""",
         """$final_date""",
         """$url""",
         '''$(echo "$description" | head -50)''',
         '''$(echo "$transcript" | head -5000)'''))
    db.commit()
    print(f"INSERTED: $vid ({final_date})")
except Exception as e:
    print(f"DB ERROR: {e}", file=sys.stderr)
db.close()
PYEOF
}

# Save flat playlist for title lookups
if [ ! -f /tmp/natebjones-videos.txt ]; then
  yt-dlp --flat-playlist --print "%(id)s|%(title)s" --playlist-end 35 \
    "https://www.youtube.com/@NateBJones/videos" 2>/dev/null > /tmp/natebjones-videos.txt || true
fi

echo "=== Fetching transcripts for ${#ORDER[@]} videos ==="
echo ""

for vid in "${ORDER[@]}"; do
  fetch_transcript "$vid"
  # Small delay to avoid hammering Gemini
  sleep 2
done

echo ""
echo "=== Inserting into SQLite ==="

for vid in "${ORDER[@]}"; do
  insert_to_db "$vid"
done

echo ""
echo "=== Done ==="
sqlite3 "$DB" "SELECT count(*), min(publish_date), max(publish_date) FROM videos;"
