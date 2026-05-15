#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../scripts/lib/behavior-schema.sh"

# Happy path: emit a record matching the unified schema
record=$(emit_jsonl_record \
  "2026-05-04T16:19:17Z" "codex" "user" "不要 sed 盲改文件" "~" "SID-001")
expected='{"ts":"2026-05-04T16:19:17Z","tool":"codex","kind":"user","text":"不要 sed 盲改文件","cwd":"~","session_id":"SID-001"}'
[ "$record" = "$expected" ] || { echo "FAIL: $record"; exit 1; }

# Text with quote must be escaped via python3 json.dumps
record=$(emit_jsonl_record "2026-05-04T16:19:17Z" "claude" "user" 'say "hi"' "~" "SID-002")
echo "$record" | python3 -c 'import sys,json; json.loads(sys.stdin.read())' \
  || { echo "FAIL: not valid JSON: $record"; exit 1; }

echo "PASS test-emit-jsonl-record.sh"
