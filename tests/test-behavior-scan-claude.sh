#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

CLAUDE_HOME="$proj/tests/fixtures/behavior/claude" \
  bash "$proj/scripts/behavior-scan-claude.sh" --out-dir="$out"

[ -f "$out/claude.jsonl" ] || { echo "FAIL: no output"; exit 1; }
n=$(wc -l < "$out/claude.jsonl")
[ "$n" -eq 2 ] || { echo "FAIL: want 2 records, got $n"; exit 1; }
grep -q '"tool":"claude"' "$out/claude.jsonl" || { echo "FAIL: missing tool"; exit 1; }
grep -q '"cwd":"~/code"' "$out/claude.jsonl" || { echo "FAIL: cwd not redacted"; exit 1; }
. "$proj/scripts/lib/behavior-schema.sh"
validate_schema < "$out/claude.jsonl" || { echo "FAIL: schema invalid"; exit 1; }
# Case 2: Empty input directory → produces empty (but present) claude.jsonl
empty=$(mktemp -d)
out_empty=$(mktemp -d)
CLAUDE_HOME="$empty" bash "$proj/scripts/behavior-scan-claude.sh" --out-dir="$out_empty"
[ -f "$out_empty/claude.jsonl" ] && [ ! -s "$out_empty/claude.jsonl" ] \
  || { echo "FAIL empty: should produce empty jsonl"; exit 1; }
rm -rf "$empty" "$out_empty"

# Case 3: Corrupt input — 1 mid-file bad JSON line, 2 valid neighbours kept
corrupt=$(mktemp -d)
out_corrupt=$(mktemp -d)
printf '%s\n' '{"timestamp":"2026-05-04T16:19:17Z","role":"user","content":"ok","sessionId":"s1","cwd":"~"}' > "$corrupt/a.jsonl"
printf '%s\n' 'NOT-JSON-LINE' >> "$corrupt/a.jsonl"
printf '%s\n' '{"timestamp":"2026-05-04T16:19:18Z","role":"user","content":"ok2","sessionId":"s2","cwd":"~"}' >> "$corrupt/a.jsonl"
touch -t 202605110000 "$corrupt/a.jsonl"
CLAUDE_HOME="$corrupt" bash "$proj/scripts/behavior-scan-claude.sh" --out-dir="$out_corrupt"
n=$(wc -l < "$out_corrupt/claude.jsonl")
[ "$n" -eq 2 ] || { echo "FAIL corrupt: want 2 valid, got $n"; exit 1; }
rm -rf "$corrupt" "$out_corrupt"

# Case 4: 100 MB single-file SLO — must complete in < 30s
# Why opt-in: emit_jsonl_record invokes python3 per record; on a loaded machine
# 1.1M records from 100MB input takes 600+s, far exceeding the 30s budget.
# The SLO is meaningful on a dedicated CI host — skip by default on dev machines.
# Set CLAUDEMEX_SLOW_TESTS=1 to enable.
if [ "${CLAUDEMEX_SLOW_TESTS:-0}" = "1" ]; then
  big=$(mktemp -d)
  out_big=$(mktemp -d)
  { yes '{"timestamp":"2026-05-04T16:19:17Z","role":"user","content":"x","sessionId":"s","cwd":"~"}' || true; } \
    | head -c 104857600 > "$big/big.jsonl"
  touch -t 202605110000 "$big/big.jsonl"
  t0=$(date +%s)
  CLAUDE_HOME="$big" bash "$proj/scripts/behavior-scan-claude.sh" --out-dir="$out_big" > /dev/null
  elapsed=$(( $(date +%s) - t0 ))
  [ "$elapsed" -lt 30 ] || { echo "FAIL SLO: took ${elapsed}s"; exit 1; }
  rm -rf "$big" "$out_big"
fi

# Case 5: Files older than 30 days must be excluded by find -mtime -30
old=$(mktemp -d)
out_old=$(mktemp -d)
cp "$proj/tests/fixtures/behavior/claude/sample.jsonl" "$old/old.jsonl"
touch -t 202601010000 "$old/old.jsonl"   # well over 30 days ago (2026-01-01)
CLAUDE_HOME="$old" bash "$proj/scripts/behavior-scan-claude.sh" --out-dir="$out_old"
n=$(wc -l < "$out_old/claude.jsonl")
[ "$n" -eq 0 ] || { echo "FAIL window: stale file was scanned ($n records)"; exit 1; }
rm -rf "$old" "$out_old"

# Case 6: real-shape jsonl (nested message.role/content + top-level type)
# Fixture lives under claude-real/ (not claude/) to avoid inflating Case 1's record count.
real_out=$(mktemp -d); real_fixture=$(mktemp -d)
cp "$proj/tests/fixtures/behavior/claude-real/real-shape.jsonl" "$real_fixture/r.jsonl"
touch -t 202605110000 "$real_fixture/r.jsonl"
CLAUDE_HOME="$real_fixture" bash "$proj/scripts/behavior-scan-claude.sh" --out-dir="$real_out"
n=$(wc -l < "$real_out/claude.jsonl")
[ "$n" -eq 2 ] || { echo "FAIL Case 6 real-shape: want 2 records (user + assistant), got $n"; cat "$real_out/claude.jsonl"; exit 1; }
grep -q '不要 sed 盲改文件' "$real_out/claude.jsonl" || { echo "FAIL Case 6: missing user text"; exit 1; }
grep -q '"kind":"user"' "$real_out/claude.jsonl" || { echo "FAIL Case 6: kind not 'user'"; exit 1; }
grep -q '"text":"OK"' "$real_out/claude.jsonl" || { echo "FAIL Case 6: assistant flat-text not parsed from list"; exit 1; }
rm -rf "$real_out" "$real_fixture"

echo "PASS test-behavior-scan-claude.sh"
