#!/usr/bin/env bash
# usage: behavior-scan-gemini.sh --out-dir=DIR [--src=DIR]
# behavior-scan-gemini.sh — opportunistic Gemini CLI history reader.
# Real format on this machine is empty (~/.gemini/history/niu/ has no entries).
# Graceful: emits empty jsonl when nothing to parse. v1.4 will pin shape if Gemini
# CLI starts persisting structured history.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/lib/behavior-schema.sh"

OUT_DIR=""; SRC_ROOT="${GEMINI_HOME:-$HOME/.gemini}"
while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir=*) OUT_DIR="${1#--out-dir=}";;
    --src=*)     SRC_ROOT="${1#--src=}";;
    *) echo "unknown: $1" >&2; exit 1;;
  esac; shift
done
[ -n "$OUT_DIR" ] || { echo "missing --out-dir" >&2; exit 1; }
mkdir -p "$OUT_DIR"; chmod 700 "$OUT_DIR" 2>/dev/null || true
out="$OUT_DIR/gemini.jsonl"; : > "$out"; chmod 600 "$out" 2>/dev/null || true

hist="$SRC_ROOT/history"
[ -d "$hist" ] || { echo "gemini history empty: $hist" >&2; exit 0; }

out_tmp=$(mktemp)
trap 'rm -f "$out_tmp"' EXIT

# Best-effort opaque parser: any *.json under history/ as array-of-entry.
# Use __NIL__ sentinel for empty sid to survive IFS=$'\t' read field collapse.
while IFS= read -r -d '' f; do
  input=$(cat "$f")
  python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
    if isinstance(d, list):
        for entry in d:
            ts = entry.get("timestamp","") or entry.get("ts","")
            text = entry.get("text") or entry.get("content") or ""
            if text:
                # Cwd unknown for Gemini history entries; use ~ as best-effort.
                # Trailing __NIL__ avoids IFS=$'"'"'\t'"'"' read collapsing empty sid.
                print(f"{ts}\tuser\t{text}\t~\t__NIL__")
except Exception:
    pass
' <<< "$input" >> "$out_tmp" 2>/dev/null || true
done < <(find -P "$hist" -type f -name '*.json' -print0 2>/dev/null)

[ -s "$out_tmp" ] || { echo "✓ gemini.jsonl: 0 records" >&2; exit 0; }
while IFS=$'\t' read -r ts kind text cwd sid; do
  [ "$sid" = "__NIL__" ] && sid=""
  emit_jsonl_record "$ts" "gemini" "$kind" "$text" "$cwd" "$sid"
done < "$out_tmp" >> "$out"

validate_schema < "$out" >&2 || true
echo "✓ gemini.jsonl: $(wc -l < "$out") records"
