#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
# /home/<name>/ is the gap: Category 5 only covers /Users/; Category 16 adds /home/
echo "/home/alice/bar is a cwd path that should be flagged" > "$fixture/leak.md"
out=$(bash "$proj/scripts/redact-scan.sh" "$fixture" 2>&1 || true)
echo "$out" | grep -qE 'Category 16.*cwd|cwd.*Category 16|/home/alice|\[BLOCK\].*cwd' \
  || { echo "FAIL: Category 16 cwd not triggered for /home/ path. Output: $out"; exit 1; }
echo "PASS test-redact-scan-cwd.sh"
