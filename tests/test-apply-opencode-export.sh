#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)

fake_home=$(mktemp -d)
kernel_dir=$(mktemp -d)
trap 'rm -rf "$fake_home" "$kernel_dir"' EXIT

# Build minimal synthetic kernel (must have common-kernel/kernel-meta.yaml)
mkdir -p "$kernel_dir/common-kernel/rules"
echo "K_threshold: 2" > "$kernel_dir/common-kernel/kernel-meta.yaml"
echo "# CLAUDE.md kernel — synthetic test" > "$kernel_dir/common-kernel/rules/01-synthetic.md"
echo "Hello v1.3" >> "$kernel_dir/common-kernel/rules/01-synthetic.md"

# --apply writes; --force skips backup (no prior file to back up anyway)
HOME="$fake_home" bash "$proj/scripts/apply.sh" \
    --kernel="$kernel_dir" \
    --target-file="$fake_home/.claude/CLAUDE.md" \
    --apply --force

[ -f "$fake_home/.claude/CLAUDE.md" ] || { echo "FAIL: claude target missing"; exit 1; }
[ -f "$fake_home/.config/opencode/AGENTS.md" ] || { echo "FAIL: opencode export missing"; exit 1; }

# OpenCode file must start with v1.3 marker
head -1 "$fake_home/.config/opencode/AGENTS.md" | grep -q '<!-- claudemex v1.3 opportunistic export' \
    || { echo "FAIL: missing header marker"; exit 1; }

# The remaining content (after the marker line) must byte-equal the Claude target
tail -n +2 "$fake_home/.config/opencode/AGENTS.md" > "$fake_home/oc-body"
diff -q "$fake_home/.claude/CLAUDE.md" "$fake_home/oc-body" \
    || { echo "FAIL: opencode body diverges from claude"; exit 1; }

echo "PASS test-apply-opencode-export.sh"
