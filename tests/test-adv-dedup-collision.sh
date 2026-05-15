#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); out=$(mktemp -d); trap 'rm -rf "$workdir" "$out"' EXIT
. "$proj/scripts/lib/behavior-schema.sh"

# 3 paraphrases of the same correction; all start with "不要 " (marker matches).
# Phrases differ by exactly 1 additive token → all pairwise Jaccard = 0.875 >= 0.7.
# Verified: all 6 permutation orderings collapse to 1 bullet × 3 in the extractor.
emit_jsonl_record "2026-05-04T00:00:00Z" claude   user "不要 sed 盲改文件" "~" s1 > "$workdir/a.jsonl"
emit_jsonl_record "2026-05-04T00:00:01Z" codex    user "不要 sed 盲改文件啊" "~" s2 > "$workdir/b.jsonl"
emit_jsonl_record "2026-05-04T00:00:02Z" opencode user "不要 sed 盲改文件呀" "~" s3 > "$workdir/c.jsonl"

bash "$proj/scripts/correction-extractor.sh" --src="$workdir" --out="$out/merged.md"

# Expect single bullet (3 paraphrases collapsed)
n=$(grep -c '^- ' "$out/merged.md")
[ "$n" -eq 1 ] || { echo "FAIL: want 1 bullet, got $n"; cat "$out/merged.md"; exit 1; }
# Count should be ×3
grep -qE '\(×3\)' "$out/merged.md" || { echo "FAIL: missing cumulative count ×3: $(cat "$out/merged.md")"; exit 1; }
echo "PASS test-adv-dedup-collision.sh"
