#!/usr/bin/env bash
# .skip-ci
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Opt-in guard — skipped by default
if [ "${CLAUDEMEX_DOGFOOD:-0}" != "1" ]; then
  echo "SKIP: test-e2e-dogfood-real.sh (set CLAUDEMEX_DOGFOOD=1 to enable)"
  exit 0
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
out=$(mktemp -d -t "dogfood-XXXXXX")
echo "Dogfood output dir: $out"

# Run all 4 readers against REAL home dirs
bash "$proj/scripts/behavior-scan-claude.sh"   --out-dir="$out" 2>/dev/null || true
bash "$proj/scripts/behavior-scan-codex.sh"    --out-dir="$out" 2>/dev/null || true
bash "$proj/scripts/behavior-scan-gemini.sh"   --out-dir="$out" 2>/dev/null || true
bash "$proj/scripts/behavior-scan-opencode.sh" --out-dir="$out" 2>/dev/null || true

bash "$proj/scripts/correction-extractor.sh" --src="$out" --out="$out/merged-signals.md"

# Soft assertion: phrase count >= 30 if real corpus
n=$(grep -c '^- ' "$out/merged-signals.md" || true)
echo "Dogfood produced $n unique correction phrases (baseline: 30)"
[ "$n" -ge 1 ] || { echo "FAIL: 0 phrases — something broken in real data path"; exit 1; }

echo "PASS test-e2e-dogfood-real.sh ($n phrases)"
