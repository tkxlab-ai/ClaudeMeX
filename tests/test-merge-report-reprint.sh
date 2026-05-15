#!/usr/bin/env bash
# Smoke test for claudemex merge-report (reprints existing merge reports).
set -uo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SELF_DIR/.." && pwd)"
RPT="$PROJECT_ROOT/scripts/merge-report.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

TMP=$(mktemp -d); trap "rm -rf '$TMP'" EXIT

# Test 1: --help
out=$("$RPT" --help 2>&1) && rc=0 || rc=$?
echo "$out" | grep -q "claudemex merge-report" && pass "--help works" || fail "no --help: $out"

# Test 2: missing dir → exit 1
out=$("$RPT" --dir="$TMP/nope" 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "missing dir → exit 1" || fail "missing: rc=$rc"

# Test 3: dir present but reports missing → exit 1
mkdir -p "$TMP/empty-merge"
out=$("$RPT" --dir="$TMP/empty-merge" 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "dir without merge-report.md → exit 1" || fail "empty: rc=$rc"

# Test 4: full reprint (merge + drift)
mkdir -p "$TMP/good"
printf '# Merge Report — TEST\n\n- N=2 K=2\n- Common sections: 5\n' > "$TMP/good/merge-report.md"
printf '# Drift Report — TEST\n\n*No drift detected.*\n' > "$TMP/good/drift-report.md"
out=$("$RPT" --dir="$TMP/good" 2>&1) && rc=0 || rc=$?
[ "$rc" = "0" ] && pass "full reprint exits 0" || fail "full: rc=$rc"
echo "$out" | grep -q "Merge Report — TEST" && pass "reprint includes merge-report" || fail "no merge-report"
echo "$out" | grep -q "Drift Report — TEST" && pass "reprint includes drift-report" || fail "no drift-report"

# Test 5: --diff-only
out=$("$RPT" --dir="$TMP/good" --diff-only 2>&1) && rc=0 || rc=$?
[ "$rc" = "0" ] && pass "--diff-only exits 0" || fail "diff-only: rc=$rc"
echo "$out" | grep -q "Drift Report — TEST" && pass "--diff-only includes drift" || fail "no drift in diff-only"
echo "$out" | grep -q "Merge Report — TEST" && fail "--diff-only should skip merge-report" || pass "--diff-only skips merge-report"

# Test 6: full reprint with no drift-report still works (omits the === section)
mkdir -p "$TMP/merge-only"
printf '# Merge Report — TEST\n' > "$TMP/merge-only/merge-report.md"
out=$("$RPT" --dir="$TMP/merge-only" 2>&1) && rc=0 || rc=$?
[ "$rc" = "0" ] && pass "merge-only dir exits 0" || fail "merge-only: rc=$rc"

echo "==="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
