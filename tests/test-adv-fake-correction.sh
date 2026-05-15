#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); out=$(mktemp -d); trap 'rm -rf "$workdir" "$out"' EXIT
. "$proj/scripts/lib/behavior-schema.sh"

emit_jsonl_record "2026-05-04T00:00:00Z" claude user "我同事说'不要 sed 盲改'，但他错了" "~" sid1 > "$workdir/fake.jsonl"
emit_jsonl_record "2026-05-04T00:00:01Z" claude user "不要 sed 盲改文件" "~" sid2 >> "$workdir/fake.jsonl"

bash "$proj/scripts/correction-extractor.sh" --src="$workdir" --out="$out/merged.md"

# The legit correction should appear
grep -q "不要 sed 盲改文件" "$out/merged.md" || { echo "FAIL: legit correction missing"; exit 1; }
# Quoted-others starting "我同事说" should NOT be aggregated (doesn't start with marker)
! grep -q "我同事说" "$out/merged.md" || { echo "FAIL: pseudo-correction leaked"; exit 1; }
echo "PASS test-adv-fake-correction.sh"
