#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../scripts/lib/behavior-schema.sh"

# Happy: valid record passes
echo '{"ts":"2026-05-04T16:19:17Z","tool":"codex","kind":"user","text":"x","cwd":"~","session_id":"SID-001"}' \
  | validate_schema || { echo "FAIL happy"; exit 1; }

# Missing required field fails
echo '{"ts":"x","tool":"codex","kind":"user","text":"x","cwd":"~"}' \
  | validate_schema && { echo "FAIL: should reject missing session_id"; exit 1; } || true

# Unknown tool fails
echo '{"ts":"x","tool":"WRONG","kind":"user","text":"x","cwd":"~","session_id":"SID-1"}' \
  | validate_schema && { echo "FAIL: should reject unknown tool"; exit 1; } || true

echo "PASS test-validate-schema.sh"
