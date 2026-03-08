#!/usr/bin/env bash
set -u

[ "$#" -eq 1 ] || { echo "Usage: $0 <path-to-json-file>" >&2; exit 1; }
json_file="$1"
[ -f "$json_file" ] || { echo "Error: file not found: $json_file" >&2; exit 1; }

ok=0; fail=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  IFS=$'\t' read -r id text category importance <<<"$line"
  if /usr/local/bin/chart add "$id" "$text" "$category" "$importance"; then
    ok=$((ok+1))
  else
    fail=$((fail+1))
  fi
done < <(python3 -c 'import json,sys
try:d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception as e:print(f"Error: invalid JSON: {e}",file=sys.stderr);sys.exit(2)
if not isinstance(d,list):print("Error: top-level JSON must be an array",file=sys.stderr);sys.exit(2)
for i,e in enumerate(d):
  if not isinstance(e,dict):print(f"Error: entry {i} is not an object",file=sys.stderr);sys.exit(2)
  m=[k for k in ("id","text","category","importance") if k not in e]
  if m:print("Error: entry %d missing fields: %s" % (i, ", ".join(m)),file=sys.stderr);sys.exit(2)
  print("\t".join(str(e[k]).replace("\t"," ").replace("\n","\\n") for k in ("id","text","category","importance")))' "$json_file")

echo "$ok OK, $fail FAIL"
