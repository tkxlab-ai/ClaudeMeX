#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)

fake_home=$(mktemp -d)
kernel_dir=$(mktemp -d)
trap 'rm -rf "$fake_home" "$kernel_dir"' EXIT

# Build minimal synthetic kernel
mkdir -p "$kernel_dir/common-kernel/rules"
echo "K_threshold: 2" > "$kernel_dir/common-kernel/kernel-meta.yaml"
echo "test kernel" > "$kernel_dir/common-kernel/rules/01-test.md"

HOME="$fake_home" bash "$proj/scripts/apply.sh" \
    --kernel="$kernel_dir" \
    --target-file="$fake_home/.claude/CLAUDE.md" \
    --apply --force --no-opencode-export

[ -f "$fake_home/.claude/CLAUDE.md" ] || { echo "FAIL: claude target missing"; exit 1; }
[ ! -f "$fake_home/.config/opencode/AGENTS.md" ] || { echo "FAIL: opencode export should NOT exist"; exit 1; }

echo "PASS test-apply-opencode-no-export.sh"
