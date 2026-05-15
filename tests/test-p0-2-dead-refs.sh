#!/usr/bin/env bash
set -e; PASS=0; FAIL=0; TESTS_RUN=0
pass() { PASS=$((PASS+1)); TESTS_RUN=$((TESTS_RUN+1)); echo "✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); TESTS_RUN=$((TESTS_RUN+1)); echo "❌ FAIL: $1"; }

echo "=== TDD-P0-2: Dead Reference Tests ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAX="$PROJECT_ROOT/outputs/TKCC-CONF-MAX-20260420"

if [ ! -d "$MAX" ]; then
  echo "SKIP: $MAX not present (gitignored — run the generator first)"
  exit 0
fi

echo "--- Test 1: No surge_wiki_guide dead paths ---"
count=$(grep -rl 'surge_wiki_guide/' "$MAX/" --include="*.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then pass "No surge_wiki_guide dead paths"; else fail "$count files still have dead paths"; fi

echo "--- Test 2: Surge refs point to official docs ---"
count=$(grep -rl 'manual.nssurge.com' "$MAX/" --include="*.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" -ge 3 ]; then pass "3+ Surge refs now point to official docs"; else fail "Only $count files have official docs refs"; fi

echo "--- Test 3: CLAUDE.md anti-pattern table updated ---"
if grep -q 'manual.nssurge.com' "$MAX/CLAUDE.md" 2>/dev/null; then pass "CLAUDE.md table updated"; else fail "CLAUDE.md table not updated"; fi

echo
echo "=== Results: $PASS passed, $FAIL failed ($TESTS_RUN tests) ==="
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
