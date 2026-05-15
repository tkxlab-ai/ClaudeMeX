#!/usr/bin/env bash
# Unit test: lib/vote-sections.sh — table-driven majority vote
set -uo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SELF_DIR/.." && pwd)"
LIB="$PROJECT_ROOT/scripts/lib/vote-sections.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

# shellcheck source=/dev/null
. "$LIB"

# compute_K formula: max(2, ceil(N/2))
[ "$(compute_K 1)" = "2" ] && pass "K(1)=2" || fail "K(1)=$(compute_K 1)"
[ "$(compute_K 2)" = "2" ] && pass "K(2)=2" || fail "K(2)=$(compute_K 2)"
[ "$(compute_K 3)" = "2" ] && pass "K(3)=2" || fail "K(3)=$(compute_K 3)"
[ "$(compute_K 4)" = "2" ] && pass "K(4)=2" || fail "K(4)=$(compute_K 4)"
[ "$(compute_K 5)" = "3" ] && pass "K(5)=3" || fail "K(5)=$(compute_K 5)"
[ "$(compute_K 7)" = "4" ] && pass "K(7)=4" || fail "K(7)=$(compute_K 7)"

# vote_section_hashes <K> <hash1> <hash2> ...
out=$(vote_section_hashes 2 abc abc def 2>/dev/null) && exit_ok=0 || exit_ok=$?
[ "$out" = "abc" ] && [ "$exit_ok" = "0" ] && pass "vote 2/3 → majority 'abc'" \
    || fail "got out='$out' exit=$exit_ok"

out=$(vote_section_hashes 2 abc def ghi 2>/dev/null) && exit_ok=0 || exit_ok=$?
[ -z "$out" ] && [ "$exit_ok" != "0" ] && pass "vote no consensus → empty + non-zero" \
    || fail "got out='$out' exit=$exit_ok"

out=$(vote_section_hashes 2 abc abc 2>/dev/null) && exit_ok=0 || exit_ok=$?
[ "$out" = "abc" ] && [ "$exit_ok" = "0" ] && pass "vote 2/2 → 'abc'" \
    || fail "got out='$out' exit=$exit_ok"

# Edge: empty input → fail with non-zero
out=$(vote_section_hashes 2 2>/dev/null) && exit_ok=0 || exit_ok=$?
[ "$exit_ok" != "0" ] && pass "empty hashes → exit non-zero" || fail "empty: exit=$exit_ok"

echo "==="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
