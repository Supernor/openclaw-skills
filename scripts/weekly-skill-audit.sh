#!/usr/bin/env bash
set -euo pipefail

ROOT="/root/.openclaw"
CHART_BIN="/usr/local/bin/chart"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REPORT_FILE="$(mktemp)"
CHART_FAILURES=0
trap 'rm -f "$REPORT_FILE"' EXIT

python3 - "$ROOT" "$TIMESTAMP" >"$REPORT_FILE" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
timestamp = sys.argv[2]
workspaces = sorted(root.glob("workspace-*/skills"))

FENCE_RE = re.compile(r"```.*?```", re.DOTALL)
INLINE_CODE_RE = re.compile(r"`([^`\n]+)`")
LINK_RE = re.compile(r"\[[^\]]+\]\(([^)\s]+)\)")
PATH_RE = re.compile(
    r'(?<![A-Za-z0-9._/\-\[\]])(?P<path>('
    r'~/[A-Za-z0-9._/-]+'
    r'|(?:/root|/home|/usr/local|/etc|/opt)/[A-Za-z0-9._/-]+'
    r'|\.\.?/[A-Za-z0-9._/-]+'
    r'|(?:memory|scripts|references|assets|templates|docs|examples|prompts|data)/[A-Za-z0-9._/-]+'
    r'|[A-Za-z0-9._-]+\.(?:sh|py|md|json|jsonl|yaml|yml|txt|sql|js|ts|tsx|jsx|toml)'
    r'))(?![A-Za-z0-9._/\-\[\]])'
)
EXTENSIONS = (
    ".sh", ".py", ".md", ".json", ".jsonl", ".yaml", ".yml", ".txt",
    ".sql", ".js", ".ts", ".tsx", ".jsx", ".toml",
)
IGNORED_PREFIXES = (
    "/api/",
    "/tmp/",
    "/var/log/",
    "/issues/",
    "/pulls/",
    "/channels/",
    "/tools/",
    "/memory/",
)
IGNORED_EXACT = {
    "SKILL.md",
    "skill.md",
}

def normalize(raw: str) -> str:
    return raw.strip().strip('`\'"()[]{}<>.,:;')

def should_skip(raw: str) -> bool:
    if not raw:
        return True
    if raw.startswith("-") or raw.endswith("-"):
        return True
    if "://" in raw:
        return True
    if raw.startswith("/usr/bin/env"):
        return True
    if raw.startswith("/#"):
        return True
    if raw.startswith("//"):
        return True
    if any(ch in raw for ch in ("*", "?", "$", "|", ":", "\\")):
        return True
    if raw in IGNORED_EXACT:
        return True
    if raw.startswith(IGNORED_PREFIXES):
        return True
    if raw.startswith("/") and not raw.startswith(("/root/", "/home/", "/usr/local/", "/etc/", "/opt/")):
        return True
    if raw.endswith("/"):
        raw = raw[:-1]
    if not raw:
        return True
    parts = [p for p in raw.split("/") if p not in (".", "..", "~", "")]
    if any(part.startswith("<") or part.endswith(">") for part in parts):
        return True
    if parts and all(part.isupper() for part in parts):
        return True
    return False

def candidate_paths(root: Path, workspace_root: Path, skill_dir: Path, raw: str):
    candidates = []
    text = raw.rstrip("/")
    if text.startswith("~/"):
        candidates.append(Path.home() / text[2:])
    elif text.startswith("/"):
        candidates.append(Path(text))
    elif text.startswith("./") or text.startswith("../"):
        candidates.append((skill_dir / text).resolve())
    elif "/" in text:
        candidates.append((skill_dir / text).resolve())
        candidates.append((workspace_root / text).resolve())
        candidates.append((root / text).resolve())
    else:
        candidates.append((skill_dir / text).resolve())
        candidates.append((workspace_root / text).resolve())
        candidates.append((root / "scripts" / text).resolve())
        candidates.append((root / text).resolve())
    uniq = []
    seen = set()
    for path in candidates:
        key = str(path)
        if key not in seen:
            uniq.append(path)
            seen.add(key)
    return uniq

def issue_id(workspace: str, skill: str, ref: str) -> str:
    import hashlib
    digest = hashlib.sha1(f"{workspace}:{skill}:{ref}".encode()).hexdigest()[:10]
    base = f"issue-skill-dependency-{workspace}-{skill}-{digest}"
    return re.sub(r"[^a-z0-9-]", "-", base.lower())

def extract_references(content: str):
    chunks = []
    chunks.extend(FENCE_RE.findall(content))
    chunks.extend(match.group(1) for match in INLINE_CODE_RE.finditer(content))
    chunks.extend(match.group(1) for match in LINK_RE.finditer(content))
    seen = set()
    ordered = []
    for chunk in chunks:
        for match in PATH_RE.finditer(chunk):
            raw = normalize(match.group("path"))
            if raw in seen or should_skip(raw):
                continue
            # Keep relative directory patterns only when they still look file-like.
            if "/" in raw and not raw.startswith(("/", "~/", "./", "../")):
                last = raw.rsplit("/", 1)[-1]
                if "." not in last:
                    continue
            elif "/" not in raw and not raw.endswith(EXTENSIONS):
                continue
            seen.add(raw)
            ordered.append(raw)
    return ordered

skill_dirs = []
audited = []
issues = []

for skills_root in workspaces:
    skill_dirs.append(str(skills_root))
    workspace = skills_root.parent.name
    workspace_root = skills_root.parent
    for skill_dir in sorted(p for p in skills_root.iterdir() if p.is_dir()):
        skill_name = skill_dir.name
        skill_file = skill_dir / "SKILL.md"
        entry = {
            "workspace": workspace,
            "skill": skill_name,
            "skill_dir": str(skill_dir),
            "skill_file": str(skill_file),
            "status": "ok",
            "references_checked": 0,
            "issues": [],
        }
        if not skill_file.exists():
            entry["status"] = "broken"
            issue = {
                "id": issue_id(workspace, skill_name, "missing-skill-md"),
                "workspace": workspace,
                "skill": skill_name,
                "ref": "SKILL.md",
                "resolved": str(skill_file),
                "kind": "skill-file",
                "message": "SKILL.md missing from skill directory",
            }
            entry["issues"].append(issue)
            issues.append(issue)
            audited.append(entry)
            continue

        content = skill_file.read_text(encoding="utf-8", errors="ignore")
        for raw in extract_references(content):
            candidates = candidate_paths(root, workspace_root, skill_dir, raw)
            entry["references_checked"] += 1
            if any(candidate.exists() for candidate in candidates):
                continue
            issue = {
                "id": issue_id(workspace, skill_name, raw),
                "workspace": workspace,
                "skill": skill_name,
                "ref": raw,
                "resolved": str(candidates[0]) if candidates else raw,
                "kind": "dependency",
                "message": "Referenced path does not exist",
            }
            entry["issues"].append(issue)
            issues.append(issue)

        if entry["issues"]:
            entry["status"] = "broken"
        audited.append(entry)

report = {
    "generated_at": timestamp,
    "skill_dirs": skill_dirs,
    "summary": {
        "skill_dirs": len(skill_dirs),
        "skills": len(audited),
        "broken_skills": sum(1 for item in audited if item["issues"]),
        "references_checked": sum(item["references_checked"] for item in audited),
        "broken_dependencies": len(issues),
    },
    "skills": audited,
    "issues": issues,
}

json.dump(report, sys.stdout)
PY

BROKEN_COUNT="$(jq -r '.summary.broken_dependencies' "$REPORT_FILE")"

echo "Weekly skill audit at $TIMESTAMP"
echo
echo "Skill directories:"
jq -r '.skill_dirs[]' "$REPORT_FILE"
echo
echo "Summary:"
echo "  skill dirs: $(jq -r '.summary.skill_dirs' "$REPORT_FILE")"
echo "  skills: $(jq -r '.summary.skills' "$REPORT_FILE")"
echo "  references checked: $(jq -r '.summary.references_checked' "$REPORT_FILE")"
echo "  broken skills: $(jq -r '.summary.broken_skills' "$REPORT_FILE")"
echo "  broken dependencies: $BROKEN_COUNT"
echo

if [ "$BROKEN_COUNT" -eq 0 ]; then
  echo "No broken dependencies found."
  exit 0
fi

echo "Broken dependencies:"
jq -r '.issues[] | "- \(.workspace)/\(.skill): \(.ref) -> \(.resolved) (\(.message))"' "$REPORT_FILE"
echo

while IFS= read -r issue_json; do
  id="$(jq -r '.id' <<<"$issue_json")"
  workspace="$(jq -r '.workspace' <<<"$issue_json")"
  skill="$(jq -r '.skill' <<<"$issue_json")"
  ref="$(jq -r '.ref' <<<"$issue_json")"
  resolved="$(jq -r '.resolved' <<<"$issue_json")"
  message="$(jq -r '.message' <<<"$issue_json")"
  chart_text="WHAT: ${workspace}/${skill} references missing dependency ${ref}. WHY: weekly-skill-audit resolved it to ${resolved} and it does not exist. FIX: update ${workspace}/${skill}/SKILL.md or restore the missing file. Verified: $(date -u +%Y-%m-%d)."

  if ! timeout 30 "$CHART_BIN" add "$id" "$chart_text" issue 0.74 >/dev/null 2>&1; then
    if ! timeout 30 "$CHART_BIN" update "$id" "$chart_text" issue 0.74 >/dev/null 2>&1; then
      CHART_FAILURES=$((CHART_FAILURES + 1))
      echo "WARN: failed to chart issue $id" >&2
    fi
  fi
done < <(jq -c '.issues[]' "$REPORT_FILE")

echo "Charted $BROKEN_COUNT issue(s)."

if [ "$CHART_FAILURES" -gt 0 ]; then
  echo "WARN: failed to chart $CHART_FAILURES issue(s)." >&2
  exit 2
fi
