#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
echo "session_id=019df3c9-6a15-70c2-8bd9-b20fbbdacdeb" > "$fixture/sid.md"
out=$(bash "$proj/scripts/redact-scan.sh" "$fixture" 2>&1 || true)
echo "$out" | grep -qE '\[BLOCK\].*(session_id UUID|019df3c9)' \
  || { echo "FAIL UUID: expected BLOCK for session_id UUID pattern. Output: $out"; exit 1; }
echo "PASS test-redact-scan-session-id.sh"
