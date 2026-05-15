#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); out=$(mktemp -d); trap 'rm -rf "$workdir" "$out"' EXIT

# Plant a secret target
mkdir -p "$workdir/sensitive"
echo "SECRET_TOKEN=AAAAA" > "$workdir/sensitive/secret.txt"

# Create fixture dir with a symlink masquerading as jsonl
mkdir -p "$workdir/fixture"
ln -s "$workdir/sensitive/secret.txt" "$workdir/fixture/foo.jsonl"

# Run reader — must NOT include secret content in output
CLAUDE_HOME="$workdir/fixture" bash "$proj/scripts/behavior-scan-claude.sh" --out-dir="$out" 2>/dev/null || true

if grep -q "SECRET_TOKEN" "$out/claude.jsonl" 2>/dev/null; then
  echo "FAIL: secret content leaked via symlink"; exit 1
fi
echo "PASS test-adv-symlink-jsonl.sh"
