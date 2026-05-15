#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT

CODEX_HOME="$proj/tests/fixtures/behavior/codex" \
  bash "$proj/scripts/behavior-scan-codex.sh" --out-dir="$out"

[ -f "$out/codex.jsonl" ] || { echo "FAIL: no output"; exit 1; }
grep -q '"tool":"codex"' "$out/codex.jsonl" || { echo "FAIL: tool"; exit 1; }
grep -q '"cwd":"~/tktemp"' "$out/codex.jsonl" || { echo "FAIL: cwd redact"; exit 1; }
grep -q '必须先 read 再 edit' "$out/codex.jsonl" || { echo "FAIL: user msg"; exit 1; }
. "$proj/scripts/lib/behavior-schema.sh"
validate_schema < "$out/codex.jsonl"
# Case 2: multi-year session tree (2025/12 + 2026/05 both discovered)
grep -q 'sid-old' "$out/codex.jsonl" || { echo "FAIL multi-year: old session not in output"; exit 1; }
grep -q 'old session message' "$out/codex.jsonl" || { echo "FAIL multi-year: old text missing"; exit 1; }

# Case 3: cross-user cwd collapses to <other>:~/... form
grep -q '"cwd":"<kaufmann>:~/work"' "$out/codex.jsonl" || { echo "FAIL other-user: cwd not collapsed"; exit 1; }

# Case 4: corruption_rate emitted to stderr (1 bad out of 11 = "1/11")
stderr=$(mktemp)
CODEX_HOME="$proj/tests/fixtures/behavior/codex" \
  bash "$proj/scripts/behavior-scan-codex.sh" --out-dir="$out.corrupt" 2>"$stderr"
grep -q 'corruption_rate=1/11' "$stderr" || { echo "FAIL corruption_rate: $(cat "$stderr")"; exit 1; }
# Good lines (5+4=9) made it through (the corrupt line was skipped)
n=$(grep -c '"text":"good ' "$out.corrupt/codex.jsonl")
[ "$n" -eq 9 ] || { echo "FAIL corrupt: want 9 good text records, got $n"; exit 1; }
rm -f "$stderr"

# Case 5: session_index thread_name records emitted
grep -q '"kind":"thread_name"' "$out/codex.jsonl" || { echo "FAIL session_index: no thread_name kind"; exit 1; }
grep -q 'v1.3 multi-CLI plan brainstorm' "$out/codex.jsonl" || { echo "FAIL session_index: name missing"; exit 1; }

# Case 6: blacklisted files (auth.json, installation_id) must not leak into output
! grep -q 'Bearer ' "$out/codex.jsonl" || { echo "FAIL blacklist: Bearer leaked"; exit 1; }
! grep -q 'access_token' "$out/codex.jsonl" || { echo "FAIL blacklist: access_token leaked"; exit 1; }
! grep -q 'fake-install-id' "$out/codex.jsonl" || { echo "FAIL blacklist: installation_id leaked"; exit 1; }

# Case 7: real Codex shape — user_message / agent_message + newline-in-text (M-2 fix)
real_out=$(mktemp -d)
real_fixture="$proj/tests/fixtures/behavior/codex"
CODEX_HOME="$real_fixture" bash "$proj/scripts/behavior-scan-codex.sh" --out-dir="$real_out" 2>/dev/null
# user_message → kind=user
grep -q '必须 read 后再 edit' "$real_out/codex.jsonl" \
  || { echo "FAIL Case 7 user_message: missing text"; exit 1; }
grep -q 'Understood. Will read first' "$real_out/codex.jsonl" \
  || { echo "FAIL Case 7 agent_message: missing text"; exit 1; }
# Newline in text must NOT corrupt downstream records — both parts of multi-line message present
grep -q "don't forget the newline" "$real_out/codex.jsonl" \
  || { echo "FAIL Case 7 newline body: missing first part"; exit 1; }
grep -q "here is a code block" "$real_out/codex.jsonl" \
  || { echo "FAIL Case 7 newline body: missing second part (newline corrupted field)"; exit 1; }
# token_count must be SKIPPED (not emitted as user/assistant)
! grep -q '"kind":"user".*"text":"42"' "$real_out/codex.jsonl" \
  || { echo "FAIL Case 7: token_count leaked as user record"; exit 1; }
# Verify all records are valid JSON (no TSV pollution)
while IFS= read -r line; do
  [ -z "$line" ] && continue
  echo "$line" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' \
    || { echo "FAIL Case 7: invalid JSON line: $line"; exit 1; }
done < "$real_out/codex.jsonl"
rm -rf "$real_out"

echo "PASS test-behavior-scan-codex.sh basic"
