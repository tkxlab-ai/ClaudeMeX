#!/usr/bin/env bash
# usage: test-prompt-dual-source.sh
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
diff -q "$proj/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md" \
        "$proj/skills/claudemex/assets/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md" \
  || { echo "FAIL: root prompt drifted from assets mirror"; exit 1; }
echo "PASS test-prompt-dual-source.sh"
