#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
src=$(mktemp -d); out=$(mktemp -d); trap 'rm -rf "$src" "$out"' EXIT

. "$proj/scripts/lib/behavior-schema.sh"
emit_jsonl_record "2026-05-04T16:19:17Z" claude user "不要 sed 盲改文件" "~" sid1 > "$src/claude.jsonl"
emit_jsonl_record "2026-05-04T16:19:17Z" codex user "必须 read 后再 edit" "~" sid2 > "$src/codex.jsonl"
emit_jsonl_record "2026-05-04T16:19:17Z" opencode user "don't bypass redact-scan" "~" sid3 > "$src/opencode.jsonl"

bash "$proj/scripts/correction-extractor.sh" --src="$src" --out="$out/merged-signals.md"
grep -q "不要 sed 盲改" "$out/merged-signals.md" || { echo "FAIL: claude marker"; exit 1; }
grep -q "必须 read"     "$out/merged-signals.md" || { echo "FAIL: codex marker"; exit 1; }
grep -q "don't bypass"  "$out/merged-signals.md" || { echo "FAIL: opencode marker"; exit 1; }
echo "PASS test-correction-extractor.sh basic"

# Case 2: paraphrases sharing enough tokens collapse to 1 phrase via Jaccard >= 0.7
# Token math (ASCII words + individual CJK chars):
#   "不要 sed 盲改文件"   → {不,要,sed,盲,改,文,件} = 7
#   "不要 sed 盲改文件吗" → {不,要,sed,盲,改,文,件,吗} = 8  inter=7 union=8 J=0.875 ✓
#   "不要再 sed 盲改文件" → {不,要,再,sed,盲,改,文,件} = 8  inter=7 union=8 J=0.875 ✓
src2=$(mktemp -d); out2=$(mktemp -d)
emit_jsonl_record "2026-05-04T16:19:17Z" claude   user "不要 sed 盲改文件"    "~" sa > "$src2/a.jsonl"
emit_jsonl_record "2026-05-04T16:19:18Z" codex    user "不要 sed 盲改文件吗"  "~" sb > "$src2/b.jsonl"
emit_jsonl_record "2026-05-04T16:19:19Z" opencode user "不要再 sed 盲改文件"  "~" sc > "$src2/c.jsonl"
bash "$proj/scripts/correction-extractor.sh" --src="$src2" --out="$out2/merged-signals.md"
# Count bullet lines (lines starting with "- ")
n=$(grep -c '^- ' "$out2/merged-signals.md")
[ "$n" -eq 1 ] || { echo "FAIL fuzzy: want 1 deduped phrase, got $n"; cat "$out2/merged-signals.md"; exit 1; }
rm -rf "$src2" "$out2"
echo "PASS test-correction-extractor.sh fuzzy-dedup"

# Case 3: run extractor 3× on same input → byte-equal outputs
src3=$(mktemp -d); out3=$(mktemp -d)
emit_jsonl_record "2026-05-04T16:00:00Z" claude   user "不要 sed 盲改"   "~" sa > "$src3/a.jsonl"
emit_jsonl_record "2026-05-04T16:00:01Z" codex    user "必须 verify"     "~" sb > "$src3/b.jsonl"
emit_jsonl_record "2026-05-04T16:00:02Z" opencode user "always validate" "~" sc > "$src3/c.jsonl"
emit_jsonl_record "2026-05-04T16:00:03Z" gemini   user "never bypass"    "~" sd > "$src3/d.jsonl"

bash "$proj/scripts/correction-extractor.sh" --src="$src3" --out="$out3/run1.md"
bash "$proj/scripts/correction-extractor.sh" --src="$src3" --out="$out3/run2.md"
bash "$proj/scripts/correction-extractor.sh" --src="$src3" --out="$out3/run3.md"
diff -q "$out3/run1.md" "$out3/run2.md" || { echo "FAIL determinism: 1 != 2"; exit 1; }
diff -q "$out3/run2.md" "$out3/run3.md" || { echo "FAIL determinism: 2 != 3"; exit 1; }
rm -rf "$src3" "$out3"
echo "PASS test-correction-extractor.sh determinism"

# Case 4: assistant_action lines must not be aggregated even if they start with markers
src4=$(mktemp -d); out4=$(mktemp -d)
emit_jsonl_record "2026-05-04T16:30:00Z" claude   user             "禁止 commit secrets" "~" sa > "$src4/a.jsonl"
emit_jsonl_record "2026-05-04T16:30:01Z" claude   assistant_action "always validate input" "~" sa >> "$src4/a.jsonl"
emit_jsonl_record "2026-05-04T16:30:02Z" codex    assistant        "must verify before merging" "~" sb > "$src4/b.jsonl"
bash "$proj/scripts/correction-extractor.sh" --src="$src4" --out="$out4/merged-signals.md"
# Only the user line should be aggregated:
grep -q '禁止 commit' "$out4/merged-signals.md" || { echo "FAIL: user marker missing"; exit 1; }
! grep -q 'always validate input' "$out4/merged-signals.md" || { echo "FAIL: assistant_action leaked"; exit 1; }
! grep -q 'must verify before' "$out4/merged-signals.md" || { echo "FAIL: assistant leaked"; exit 1; }
rm -rf "$src4" "$out4"
echo "PASS test-correction-extractor.sh assistant-kind-filter"

# Case 5: empty --src dir produces a valid header-only merged-signals.md
src5=$(mktemp -d); out5=$(mktemp -d)
bash "$proj/scripts/correction-extractor.sh" --src="$src5" --out="$out5/merged-signals.md"
[ -f "$out5/merged-signals.md" ] || { echo "FAIL: no output file"; exit 1; }
grep -q '^# Merged correction signals' "$out5/merged-signals.md" || { echo "FAIL: header missing"; exit 1; }
# No bullet lines expected
n=$(grep -c '^- ' "$out5/merged-signals.md" || true)
[ "$n" -eq 0 ] || { echo "FAIL empty: $n bullets found, want 0"; cat "$out5/merged-signals.md"; exit 1; }
rm -rf "$src5" "$out5"
echo "PASS test-correction-extractor.sh empty-input"
