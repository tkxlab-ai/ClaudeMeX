#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); fake_home=$(mktemp -d)
trap 'rm -rf "$workdir" "$fake_home"' EXIT

# Minimal kernel (rules/ subdir — render-claude.sh reads rules/*.md)
kernel="$workdir/k"
mkdir -p "$kernel/common-kernel/rules"
cat > "$kernel/common-kernel/rules/00-base.md" <<'MD'
# kernel base
MD
cat > "$kernel/common-kernel/kernel-meta.yaml" <<'META'
version: 1.3.0
hosts: [test]
META

# Case 1: --no-opencode-export → apply produces claude target only
HOME="$fake_home/case1" bash "$proj/scripts/apply.sh" \
  --target=claude --kernel="$kernel" --apply --force --no-opencode-export \
  2>/dev/null
[ -f "$fake_home/case1/.claude/CLAUDE.md" ] || { echo "FAIL case1: claude missing"; exit 1; }
[ ! -f "$fake_home/case1/.config/opencode/AGENTS.md" ] || { echo "FAIL case1: opencode should be skipped"; exit 1; }

# Case 2: Selectively run only claude reader — codex/gemini/opencode produce no jsonl
mkdir -p "$workdir/claude-only"
cat > "$workdir/claude-only/sample.jsonl" <<JSON
{"timestamp":"2026-05-04T16:00:00Z","role":"user","content":"don't skip verification","sessionId":"s","cwd":"~"}
JSON
touch -t 202605110000 "$workdir/claude-only/sample.jsonl"

raw="$workdir/raw-claude-only"; mkdir -p "$raw"
CLAUDE_HOME="$workdir/claude-only" bash "$proj/scripts/behavior-scan-claude.sh" --out-dir="$raw" 2>/dev/null

[ -f "$raw/claude.jsonl" ]    || { echo "FAIL case2: claude.jsonl missing"; exit 1; }
[ ! -f "$raw/codex.jsonl" ]   || { echo "FAIL case2: codex.jsonl should be absent (not run)"; exit 1; }
[ ! -f "$raw/gemini.jsonl" ]  || { echo "FAIL case2: gemini.jsonl should be absent (not run)"; exit 1; }
[ ! -f "$raw/opencode.jsonl" ] || { echo "FAIL case2: opencode.jsonl should be absent (not run)"; exit 1; }

echo "PASS test-e2e-opt-out-flags.sh"
