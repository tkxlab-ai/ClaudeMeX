#!/usr/bin/env bash
# RUN_ALL: optional
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin

if [ "${CLAUDEMEX_SLOW_TESTS:-0}" != "1" ]; then
  echo "SKIP test-adv-size-bomb.sh (set CLAUDEMEX_SLOW_TESTS=1 to enable)"
  exit 0
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); out=$(mktemp -d); trap 'rm -rf "$workdir" "$out"' EXIT

# 1 GiB single jsonl line (one giant "text" field)
big="$workdir/bomb.jsonl"
python3 - "$big" <<'PY'
import sys, json
path = sys.argv[1]
huge = "X" * (1024 * 1024 * 1024)  # 1 GiB
with open(path, "w") as fh:
    fh.write(json.dumps({"timestamp":"2026-05-04T00:00:00Z","role":"user","content":huge,"sessionId":"s","cwd":"~"}) + "\n")
PY
touch -t 202605110000 "$big"

t0=$(date +%s)
CLAUDE_HOME="$workdir" timeout 90 bash "$proj/scripts/behavior-scan-claude.sh" --out-dir="$out" 2>/dev/null || true
elapsed=$(($(date +%s) - t0))
[ "$elapsed" -lt 90 ] || { echo "FAIL: hung past 90s"; exit 1; }

# Reader should NOT crash (graceful)
echo "PASS test-adv-size-bomb.sh (${elapsed}s)"
