#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <path-to-chartroom-json>" >&2
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

input_path="$1"

if [ ! -f "$input_path" ]; then
  echo "Error: file not found: $input_path" >&2
  exit 1
fi

if [ ! -r "$input_path" ]; then
  echo "Error: file is not readable: $input_path" >&2
  exit 1
fi

python3 - "$input_path" <<'PY'
import json
import re
import sys
from collections import Counter, defaultdict

path = sys.argv[1]

try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    print(f"Error: file not found: {path}", file=sys.stderr)
    sys.exit(1)
except json.JSONDecodeError as e:
    print(f"Error: invalid JSON in {path}: {e}", file=sys.stderr)
    sys.exit(1)
except OSError as e:
    print(f"Error: unable to read {path}: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, list):
    print("Error: top-level JSON must be an array", file=sys.stderr)
    sys.exit(1)

rules = [
    "deprecated-model",
    "wrong-agent-count",
    "wrong-skill-count",
    "importance-overflow",
    "wrong-category",
    "empty-entry",
    "duplicate-id",
    "dangling-file-ref",
    "old-agent-name",
    "doing-good-as-intent",
]

findings = []
by_rule = Counter({rule: 0 for rule in rules})

ids = []
entries = []
for idx, item in enumerate(data):
    if not isinstance(item, dict):
        entry = {"id": f"<index:{idx}>", "text": "", "category": "", "importance": None}
    else:
        entry = {
            "id": str(item.get("id", f"<index:{idx}>")),
            "text": str(item.get("text", "")),
            "category": str(item.get("category", "")),
            "importance": item.get("importance", None),
        }
    ids.append(entry["id"])
    entries.append(entry)

id_counts = Counter(ids)

agent_re = re.compile(r"\b([0-9]{1,3})\s+agents\b", re.IGNORECASE)
skill_re = re.compile(r"\b([0-9]{1,3})\s+skills\b", re.IGNORECASE)
deprecated_re = re.compile(r"\b(?:gemini-3-pro|gemini-2-pro|haiku-3\.5)\b", re.IGNORECASE)
dangling_re = re.compile(r"\b(?:PLANNING-GUIDE\.md|LIMITS\.md|RESILIENCE\.md|DECISION_ENGINE\.md)\b")
old_agent_re = re.compile(r"quartermaster", re.IGNORECASE)
doing_good_re = re.compile(r"Good \[I00\]")

for entry in entries:
    eid = entry["id"]
    text = entry["text"]
    category = entry["category"]
    importance = entry["importance"]

    if deprecated_re.search(text):
        by_rule["deprecated-model"] += 1
        findings.append({"id": eid, "rule": "deprecated-model", "detail": "Contains deprecated model name"})

    for m in agent_re.finditer(text):
        n = int(m.group(1))
        if 4 <= n <= 50 and n != 13:
            by_rule["wrong-agent-count"] += 1
            findings.append({"id": eid, "rule": "wrong-agent-count", "detail": f"Mentions {n} agents (expected 13)"})
            break

    for m in skill_re.finditer(text):
        n = int(m.group(1))
        if 10 <= n <= 200 and n != 94:
            by_rule["wrong-skill-count"] += 1
            findings.append({"id": eid, "rule": "wrong-skill-count", "detail": f"Mentions {n} skills (expected 94)"})
            break

    if isinstance(importance, (int, float)) and importance > 1.0:
        by_rule["importance-overflow"] += 1
        findings.append({"id": eid, "rule": "importance-overflow", "detail": f"importance={importance} > 1.0"})

    if eid.startswith("agent-") and category != "agent":
        by_rule["wrong-category"] += 1
        findings.append({"id": eid, "rule": "wrong-category", "detail": f"id starts with 'agent-' but category is '{category}'"})

    if len(text.strip()) < 20:
        by_rule["empty-entry"] += 1
        findings.append({"id": eid, "rule": "empty-entry", "detail": "text shorter than 20 chars"})

    if dangling_re.search(text):
        by_rule["dangling-file-ref"] += 1
        findings.append({"id": eid, "rule": "dangling-file-ref", "detail": "References deprecated internal file name"})

    if old_agent_re.search(text):
        by_rule["old-agent-name"] += 1
        findings.append({"id": eid, "rule": "old-agent-name", "detail": "Contains deprecated agent name 'quartermaster'"})

    if doing_good_re.search(text):
        by_rule["doing-good-as-intent"] += 1
        findings.append({"id": eid, "rule": "doing-good-as-intent", "detail": "Contains literal 'Good [I00]'"})

for eid, count in id_counts.items():
    if count > 1:
        for _ in range(count):
            by_rule["duplicate-id"] += 1
            findings.append({"id": eid, "rule": "duplicate-id", "detail": f"id appears {count} times"})

out = {
    "total_entries_scanned": len(entries),
    "total_findings": len(findings),
    "by_rule": dict(by_rule),
    "findings": findings,
}

json.dump(out, sys.stdout, ensure_ascii=False)
sys.stdout.write("\n")
PY
