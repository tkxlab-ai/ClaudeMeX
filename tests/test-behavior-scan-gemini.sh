#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
# Case 1: src dir exists but has no history/ subdir — graceful empty
# Use a fresh tmpdir (no history/ subdir) as --src to avoid picking up Case 2 fixture.
src_empty=$(mktemp -d); trap 'rm -rf "$src_empty"' EXIT
bash "$proj/scripts/behavior-scan-gemini.sh" --src="$src_empty" --out-dir="$out"
[ -f "$out/gemini.jsonl" ] || { echo "FAIL: no output"; exit 1; }
[ ! -s "$out/gemini.jsonl" ] || { echo "FAIL: expected empty, got $(wc -l < "$out/gemini.jsonl") lines"; exit 1; }
echo "PASS test-behavior-scan-gemini.sh empty"

# Case 2: synthetic history file with 2 entries parses
out2=$(mktemp -d); trap 'rm -rf "$out2"' EXIT
bash "$proj/scripts/behavior-scan-gemini.sh" \
  --src="$proj/tests/fixtures/behavior/gemini" --out-dir="$out2"
n=$(wc -l < "$out2/gemini.jsonl")
[ "$n" -eq 2 ] || { echo "FAIL: want 2 records, got $n"; exit 1; }
grep -q "don't sed blind" "$out2/gemini.jsonl" || { echo "FAIL: missing text"; exit 1; }
grep -q '"tool":"gemini"' "$out2/gemini.jsonl" || { echo "FAIL: tool field missing"; exit 1; }
. "$proj/scripts/lib/behavior-schema.sh"
validate_schema < "$out2/gemini.jsonl"
echo "PASS test-behavior-scan-gemini.sh 2-records"
