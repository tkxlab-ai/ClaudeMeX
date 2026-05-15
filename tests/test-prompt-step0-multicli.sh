#!/usr/bin/env bash
# usage: test-prompt-step0-multicli.sh
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
for kw in "~/.codex/sessions" "~/.gemini/history" "opencode.db" "behavior-raw/"; do
  grep -q "$kw" "$proj/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md" \
    || { echo "FAIL: missing keyword $kw"; exit 1; }
done
# cwd redaction must be mentioned
grep -qE "(cwd.*redact|redact_cwd|cwd 脱敏)" "$proj/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md" \
  || { echo "FAIL: cwd redaction not mentioned"; exit 1; }
echo "PASS test-prompt-step0-multicli.sh"
