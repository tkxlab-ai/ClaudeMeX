#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
diff -q "$proj/scripts/redact-scan.sh" "$proj/Release/redact-scan.sh" \
  || { echo "FAIL: scripts/ and Release/ redact-scan.sh diverged"; exit 1; }
echo "PASS test-redact-scan-dual-source.sh"
