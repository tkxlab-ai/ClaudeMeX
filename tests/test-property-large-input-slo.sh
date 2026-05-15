#!/usr/bin/env bash
# RUN_ALL: optional
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Opt-in guard — skipped by default
if [ "${CLAUDEMEX_SLOW_TESTS:-0}" != "1" ]; then
  echo "SKIP: test-property-large-input-slo.sh (set CLAUDEMEX_SLOW_TESTS=1 to enable)"
  exit 0
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); trap 'rm -rf "$workdir"' EXIT

# Generate 1 GiB Codex rollout fixture
mkdir -p "$workdir/codex/sessions/2026/05/04"
big="$workdir/codex/sessions/2026/05/04/rollout-big.jsonl"
echo '{"timestamp":"2026-05-04T16:19:17Z","type":"session_meta","payload":{"id":"sid-big","cwd":"/Users/niu/c","originator":"CodexCli"}}' > "$big"
# Append 1 GiB of event_msg lines
python3 - "$big" <<'PY'
import sys
path = sys.argv[1]
line = '{"timestamp":"2026-05-04T16:19:18Z","type":"event_msg","payload":{"type":"user_input","text":"x"}}\n'
target = 1024 * 1024 * 1024  # 1 GiB
written = 0
with open(path, "a") as fh:
    while written < target:
        fh.write(line)
        written += len(line)
PY
touch -t 202605110000 "$big"

# Time it
t0=$(date +%s)
CODEX_HOME="$workdir/codex" bash "$proj/scripts/behavior-scan-codex.sh" --out-dir="$workdir/raw" > /dev/null 2>&1
elapsed=$(($(date +%s) - t0))
[ "$elapsed" -lt 60 ] || { echo "FAIL SLO: ${elapsed}s > 60s"; exit 1; }
echo "PASS test-property-large-input-slo.sh (${elapsed}s)"
