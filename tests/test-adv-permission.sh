#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
fake_home=$(mktemp -d); kernel=$(mktemp -d)
trap 'chmod u+w "$fake_home/.config/opencode/AGENTS.md" 2>/dev/null || true; rm -rf "$fake_home" "$kernel"' EXIT

mkdir -p "$kernel/common-kernel"
cat > "$kernel/common-kernel/CLAUDE.md" <<'MD'
# kernel
MD
cat > "$kernel/common-kernel/kernel-meta.yaml" <<'META'
version: 1.3.0
hosts: [test]
META

# Pre-create AGENTS.md as read-only
mkdir -p "$fake_home/.config/opencode"
echo "PROTECTED-DO-NOT-OVERWRITE" > "$fake_home/.config/opencode/AGENTS.md"
chmod 444 "$fake_home/.config/opencode/AGENTS.md"

stderr=$(mktemp); trap 'chmod u+w "$fake_home/.config/opencode/AGENTS.md" 2>/dev/null || true; rm -rf "$fake_home" "$kernel" "$stderr"' EXIT
HOME="$fake_home" bash "$proj/scripts/apply.sh" --target=claude --kernel="$kernel" --apply --force 2>"$stderr" || true

# Read-only protection respected
grep -q 'PROTECTED-DO-NOT-OVERWRITE' "$fake_home/.config/opencode/AGENTS.md" \
  || { echo "FAIL: read-only AGENTS.md overwritten"; exit 1; }

# Advisory in stderr
grep -qE '(permission|cannot write|read-only|⚠)' "$stderr" \
  || { echo "FAIL: missing permission advisory in stderr: $(cat "$stderr")"; exit 1; }

echo "PASS test-adv-permission.sh"
