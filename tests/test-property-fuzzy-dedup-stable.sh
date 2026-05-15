#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); trap 'rm -rf "$workdir"' EXIT
. "$proj/scripts/lib/behavior-schema.sh"

# Generate 100 user-corrections (mix of paraphrases that should dedup)
seeds=("不要 sed 盲改文件" "不要 sed 盲改文件吗" "不要再 sed 盲改文件"
       "必须先 read 再 edit" "必须 read 后再 edit" "must verify after deploy"
       "don't bypass redact" "禁止 commit secrets" "记住 always backup"
       "stop reviewing your own code" "remember to test edge cases" "always document why")
src_base="$workdir/src-base"; mkdir -p "$src_base"
n=0
for seed in "${seeds[@]}"; do
  for i in 1 2 3 4 5 6 7 8; do
    n=$((n+1))
    emit_jsonl_record "2026-05-04T16:00:0${i}Z" claude user "$seed" "~" "sid-$n" >> "$src_base/all.jsonl"
  done
done

# Run extractor 3 times — input file is the same, but check determinism
bash "$proj/scripts/correction-extractor.sh" --src="$src_base" --out="$workdir/run1.md"
bash "$proj/scripts/correction-extractor.sh" --src="$src_base" --out="$workdir/run2.md"
bash "$proj/scripts/correction-extractor.sh" --src="$src_base" --out="$workdir/run3.md"

diff -q "$workdir/run1.md" "$workdir/run2.md" || { echo "FAIL: run 1 != run 2"; exit 1; }
diff -q "$workdir/run2.md" "$workdir/run3.md" || { echo "FAIL: run 2 != run 3"; exit 1; }
echo "PASS test-property-fuzzy-dedup-stable.sh"
