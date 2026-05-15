#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)

fake_home=$(mktemp -d)
kernel_dir=$(mktemp -d)
stderr=$(mktemp)
trap 'rm -rf "$fake_home" "$kernel_dir" "$stderr"' EXIT

# Build minimal synthetic kernel
mkdir -p "$kernel_dir/common-kernel/rules"
echo "K_threshold: 2" > "$kernel_dir/common-kernel/kernel-meta.yaml"
echo "test kernel" > "$kernel_dir/common-kernel/rules/01-test.md"

# Pre-create the Claude file then symlink ~/AGENTS.md to it
mkdir -p "$fake_home/.claude"
echo "existing claude content" > "$fake_home/.claude/CLAUDE.md"
ln -s "$fake_home/.claude/CLAUDE.md" "$fake_home/AGENTS.md"

HOME="$fake_home" bash "$proj/scripts/apply.sh" \
    --kernel="$kernel_dir" \
    --target-file="$fake_home/.claude/CLAUDE.md" \
    --apply --force 2>"$stderr" || true

grep -q 'symlink detected' "$stderr" \
    || { echo "FAIL: missing symlink advisory. stderr: $(cat "$stderr")"; exit 1; }
grep -qE 'rm.*AGENTS\.md' "$stderr" \
    || { echo "FAIL: missing remediation hint. stderr: $(cat "$stderr")"; exit 1; }

echo "PASS test-apply-symlink-advisory.sh"
