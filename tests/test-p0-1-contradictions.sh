#!/usr/bin/env bash
# TDD test for P0-1: No M1↔M3 contradictions in MAX outputs
set -e
PASS=0; FAIL=0; TESTS_RUN=0
pass() { PASS=$((PASS+1)); TESTS_RUN=$((TESTS_RUN+1)); echo "✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); TESTS_RUN=$((TESTS_RUN+1)); echo "❌ FAIL: $1"; }

echo "=== TDD-P0-1: M1↔M3 Contradiction Tests ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAX="$PROJECT_ROOT/outputs/TKCC-CONF-MAX-20260420"

# outputs/ is gitignored (per-machine generator output). When absent — fresh
# clone, CI runner, gitx-release worktree — skip rather than fail.
if [ ! -d "$MAX" ]; then
  echo "SKIP: $MAX not present (gitignored — run the generator first)"
  exit 0
fi

# Test 1: No "M1 Max" or "M1 Pro" in machine identifiers (except historical bug ref in INDEX)
echo "--- Test 1: No M1 machine ID contradictions ---"
count=$(grep -rn 'Apple M1\|M1 Max\|M1 Pro' "$MAX/" --include="*.md" 2>/dev/null | grep -v '命名 bug' | grep -v 'M1 Max → Max' | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
  pass "No M1 machine ID contradictions"
else
  fail "Found $count files with M1 machine ID contradictions"
fi

# Test 2: Machine name is consistent across files
# Parameterized: extract whatever machine codename appears in INDEX.md
# (avoids hardcoding the author's private machine name into the test source).
echo "--- Test 2: machine-name consistency ---"
idx_machine=$(grep '机器' "$MAX/INDEX.md" | grep -oE '[A-Z][A-Z0-9-]+-M[0-9]+' | head -1 || true)
if [ -n "$idx_machine" ] \
   && grep -q "$idx_machine" "$MAX/session-inventory.md" \
   && grep -q 'Apple M[0-9]' "$MAX/rules/01-identity.md"; then
  pass "Machine name '$idx_machine' consistent across INDEX/session-inventory/01-identity"
else
  fail "Machine name inconsistent (idx='$idx_machine')"
fi

# Test 3: CLAUDE.md header matches
echo "--- Test 3: CLAUDE.md header no M1 ---"
if grep -q 'M1 Max\|M1 Pro' "$MAX/CLAUDE.md" 2>/dev/null; then
  fail "CLAUDE.md still contains M1 reference"
else
  pass "CLAUDE.md header M1-free"
fi

# Test 4: INDEX bug example preserved (historical)
echo "--- Test 4: Historical bug example preserved ---"
if grep -q '命名 bug' "$MAX/INDEX.md" 2>/dev/null; then
  pass "Historical bug example preserved"
else
  fail "Historical bug example lost"
fi

# Test 5: Auxiliary machine not mislabelled as M3
echo "--- Test 5: Auxiliary machine not M3 ---"
if grep '辅助' "$MAX/rules/01-identity.md" | grep -q '（M3）'; then
  fail "Auxiliary machine mislabelled as M3"
else
  pass "Auxiliary machine correctly generic"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ($TESTS_RUN tests) ==="
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
