#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); trap 'rm -rf "$workdir"' EXIT

# Fake v1.2-era output (no behavior-raw/)
v12="$workdir/host-v12-20260420"
mkdir -p "$v12/common-kernel" "$v12/per-machine-extension"
cat > "$v12/common-kernel/CLAUDE.md" <<'MD'
# v1.2 kernel — pre-v1.3
- rule: existing rule

## Memory Protocol
recall: read all memory and output status briefing

## Handoff
See HANDOFF.md for project state.

## Memory files
.memory/ structure:
- context.md — current context
- progress.md — progress snapshot
- INDEX.md — index file
MD
cat > "$v12/common-kernel/kernel-meta.yaml" <<'META'
version: 1.2.0
hosts: [v12-host]
META

# Run structural-gate against v1.2 outputs — must PASS
# structural-gate.sh looks for CLAUDE.md / memory-rule files.
# v1.2 has CLAUDE.md so it will enter the check path.
# It checks for: HANDOFF.md reference, .memory/ sub-elements, protocol triggers.
# Our v1.2 fixture has "recall:" so check 3 passes. Checks 1 and 2 are advisory
# in the context of v1.2 outputs that don't reference HANDOFF or .memory/.
# The gate only blocks on structural pointers — a v1.2 output without
# HANDOFF.md / .memory/ pointers is a pre-v1.3 artifact; gate must accept it.
result=0
bash "$proj/scripts/structural-gate.sh" "$v12" || result=$?

if [ "$result" -eq 0 ]; then
  echo "PASS test-e2e-upgrade-from-v1.2.sh"
elif [ "$result" -eq 2 ]; then
  # Bad args — unexpected
  echo "FAIL: structural-gate.sh returned exit 2 (bad args)"; exit 1
else
  # Gate failed (exit 1) — v1.2 output rejected; that's a regression
  echo "FAIL: structural-gate rejected v1.2 output (exit $result)"; exit 1
fi
