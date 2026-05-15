#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
fake_home=$(mktemp -d); kernel=$(mktemp -d); decoy=$(mktemp)
trap 'rm -rf "$fake_home" "$kernel" "$decoy"' EXIT
echo "DECOY-DO-NOT-OVERWRITE" > "$decoy"

mkdir -p "$kernel/common-kernel"
cat > "$kernel/common-kernel/CLAUDE.md" <<'MD'
# kernel
MD
cat > "$kernel/common-kernel/kernel-meta.yaml" <<'META'
version: 1.3.0
hosts: [test]
META

# Plant symlink at the OpenCode export target
mkdir -p "$fake_home/.config/opencode"
ln -s "$decoy" "$fake_home/.config/opencode/AGENTS.md"

stderr=$(mktemp); trap 'rm -rf "$fake_home" "$kernel" "$decoy" "$stderr"' EXIT
HOME="$fake_home" bash "$proj/scripts/apply.sh" --target=claude --kernel="$kernel" --apply --force 2>"$stderr" || true

# Symlink target must be unchanged
content=$(cat "$decoy")
[ "$content" = "DECOY-DO-NOT-OVERWRITE" ] || { echo "FAIL: decoy overwritten via symlink: $content"; exit 1; }

# Advisory in stderr
grep -qE '(symlink|refus)' "$stderr" || { echo "FAIL: missing symlink advisory in stderr: $(cat "$stderr")"; exit 1; }

echo "PASS test-adv-opencode-symlink-export.sh"
