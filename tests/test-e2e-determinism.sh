#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); trap 'rm -rf "$workdir"' EXIT

# Synthetic claude fixture
mkdir -p "$workdir/claude"
cat > "$workdir/claude/sample.jsonl" <<JSON
{"timestamp":"2026-05-04T16:19:17Z","role":"user","content":"不要 sed 盲改文件","sessionId":"s1","cwd":"/Users/niu/c"}
{"timestamp":"2026-05-04T16:19:18Z","role":"user","content":"必须 verify after deploy","sessionId":"s1","cwd":"/Users/niu/c"}
JSON
touch -t 202605110000 "$workdir/claude/sample.jsonl"

# Run scan + extract 3 times, compare outputs byte-equal
for i in 1 2 3; do
  raw="$workdir/raw-$i"; mkdir -p "$raw"
  CLAUDE_HOME="$workdir/claude" bash "$proj/scripts/behavior-scan-claude.sh" --out-dir="$raw" 2>/dev/null
  bash "$proj/scripts/correction-extractor.sh" --src="$raw" --out="$workdir/merged-$i.md"
done

# Compare merged-*.md (byte-equal)
diff -q "$workdir/merged-1.md" "$workdir/merged-2.md" || { echo "FAIL: merged run 1 != run 2"; exit 1; }
diff -q "$workdir/merged-2.md" "$workdir/merged-3.md" || { echo "FAIL: merged run 2 != run 3"; exit 1; }

# Compare reader output (byte-equal)
diff -q "$workdir/raw-1/claude.jsonl" "$workdir/raw-2/claude.jsonl" || { echo "FAIL: scan run 1 != run 2"; exit 1; }
diff -q "$workdir/raw-2/claude.jsonl" "$workdir/raw-3/claude.jsonl" || { echo "FAIL: scan run 2 != run 3"; exit 1; }

echo "PASS test-e2e-determinism.sh"
