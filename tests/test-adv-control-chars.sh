#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); out=$(mktemp -d); trap 'rm -rf "$workdir" "$out"' EXIT

# Fixture with BEL and zero-width space embedded in content
python3 - <<'PY' > "$workdir/control.jsonl"
import json
# Zero-width space U+200B in text
print(json.dumps({"timestamp":"2026-05-04T00:00:00Z","role":"user","content":"hello world​","sessionId":"s","cwd":"~"}))
# BEL character U+0007 in text
print(json.dumps({"timestamp":"2026-05-04T00:00:01Z","role":"user","content":"bell\x07here","sessionId":"s","cwd":"~"}))
PY
touch -t 202605110000 "$workdir/control.jsonl"

CLAUDE_HOME="$workdir" bash "$proj/scripts/behavior-scan-claude.sh" --out-dir="$out"
# Reader should produce output WITHOUT crashing
[ -f "$out/claude.jsonl" ] || { echo "FAIL: no output"; exit 1; }
. "$proj/scripts/lib/behavior-schema.sh"
validate_schema < "$out/claude.jsonl" || { echo "FAIL: control chars broke schema"; exit 1; }
echo "PASS test-adv-control-chars.sh"
