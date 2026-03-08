#!/usr/bin/env bash
set -u

root="/root/.openclaw"
pattern="$root/workspace-spec-*"

printf "Workspace Audit Report\n"
printf "Generated: %s\n\n" "$(date -u '+%Y-%m-%d %H:%M:%SZ')"

found=0
for ws in $pattern; do
  [ -d "$ws" ] || continue
  found=1
  printf "=== %s ===\n" "$(basename "$ws")"

  md_count=0
  char_total=0
  large_files=()
  claim_files=()

  while IFS= read -r -d '' f; do
    md_count=$((md_count + 1))
    chars=$(wc -m < "$f" 2>/dev/null || printf "0")
    char_total=$((char_total + chars))
    [ "$chars" -gt 3000 ] && large_files+=("${f#$ws/}")
    grep -Eiq '\b(aes|s3|encryption|backup systems?|backup)\b' "$f" && claim_files+=("${f#$ws/}")
  done < <(find "$ws" -type f -name '*.md' -print0)

  printf "Markdown files: %d\n" "$md_count"
  printf "Combined chars: %d\n" "$char_total"

  printf "Large markdown files (>3000 chars):\n"
  if [ "${#large_files[@]}" -eq 0 ]; then
    printf "  - none\n"
  else
    for f in "${large_files[@]}"; do
      printf "  - %s (consider moving to Chartroom)\n" "$f"
    done
  fi

  printf "Broken symlinks:\n"
  broken=0
  while IFS= read -r -d '' l; do
    broken=1
    printf "  - %s\n" "${l#$ws/}"
  done < <(find "$ws" -type l ! -exec test -e {} \; -print0)
  [ "$broken" -eq 0 ] && printf "  - none\n"

  printf "Potentially hallucinated claims (AES/S3/encryption/backup):\n"
  if [ "${#claim_files[@]}" -eq 0 ]; then
    printf "  - none\n"
  else
    for f in "${claim_files[@]}"; do
      printf "  - %s (possible hallucinated content, verify against actual system state)\n" "$f"
    done
  fi

  printf "\n"
done

[ "$found" -eq 0 ] && printf "No workspaces found matching %s\n" "$pattern"
exit 0
