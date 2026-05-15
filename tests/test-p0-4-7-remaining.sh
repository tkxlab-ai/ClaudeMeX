#!/usr/bin/env bash
set -e
PASS=0; FAIL=0; TESTS_RUN=0
pass() { PASS=$((PASS+1)); TESTS_RUN=$((TESTS_RUN+1)); echo "✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); TESTS_RUN=$((TESTS_RUN+1)); echo "❌ FAIL: $1"; }

echo "=== TDD-P0-4-7: Remaining P0 Fixes ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
R="$PROJECT_ROOT/README.md"
LP="$PROJECT_ROOT/Release/lite-prompt-MIN.md"
HO="$PROJECT_ROOT/HANDOFF.md"

echo "--- P0-4: README dead link ---"
if grep -q '\[English\](#)' "$R" 2>/dev/null; then fail "README still has dead [English](#) link"; else pass "README dead link removed"; fi
if grep -q 'How rules' "$R" 2>/dev/null; then pass "README rules/ section added"; else fail "README rules/ section missing"; fi

echo "--- P0-5: rules/ doc ---"
if grep -q 'not auto-loaded' "$R" 2>/dev/null; then pass "README clarifies rules/ not auto-loaded"; else fail "README missing auto-load clarification"; fi

echo "--- P0-6: Release clean + CHECKSUMS ---"
ds=$(find "$PROJECT_ROOT/Release/v1.0.1/" -name '.DS_Store' | wc -l | tr -d ' ')
if [ "$ds" -eq 0 ]; then pass "No .DS_Store in Release"; else fail "$ds .DS_Store files remain"; fi
cs=$(wc -l < "$PROJECT_ROOT/Release/v1.0.1/CHECKSUMS.txt" | tr -d ' ')
# Post-audit (2026-05-04): review/ subdirectory was removed from v1.0.1 because
# it leaked private project codenames. CHECKSUMS now scopes to the four base
# files only (CHANGELOG / LICENSE / README / generator prompt).
if [ "$cs" -ge 4 ] && [ "$cs" -le 6 ]; then
  pass "CHECKSUMS has $cs entries (base files only — review/ removed)"
else
  fail "CHECKSUMS has $cs entries — expected 4 base files, found something else"
fi

echo "--- P0-7: Low-level errors ---"
if grep -q '🚚' "$LP" 2>/dev/null; then fail "lite-prompt still has 🚚 emoji"; else pass "lite-prompt emoji consistent 🚀"; fi
# HANDOFF.md is gitignored as of v1.0.2 post-audit. Skip the line-count
# assertion when it isn't present (fresh clone, CI runner, release worktree).
if [ -f "$HO" ]; then
  if grep -q '877' "$HO" 2>/dev/null; then pass "HANDOFF generator line count updated"; else fail "HANDOFF line count stale"; fi
else
  echo "ℹ️  HANDOFF.md absent (gitignored) — skipping line-count assertion"
fi
if grep -Eq 'BRE.*\\|' "$PROJECT_ROOT/tests/test-b4-deploy.sh" 2>/dev/null; then fail "test-b4 still has BRE \\|"; else pass "test-b4 ERE compatible"; fi

echo
echo "=== Results: $PASS passed, $FAIL failed ($TESTS_RUN tests) ==="
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
