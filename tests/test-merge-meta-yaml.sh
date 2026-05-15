#!/usr/bin/env bash
# Unit test: lib/meta-yaml.sh
set -uo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SELF_DIR/.." && pwd)"
LIB="$PROJECT_ROOT/scripts/lib/meta-yaml.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

# shellcheck source=/dev/null
. "$LIB"

# Test 1: write_run_meta produces a parseable file
TMP=$(mktemp -d); trap "rm -rf '$TMP'" EXIT
write_run_meta "$TMP/run-meta.yaml" "tk-mbp16-m3" "v1.0.6" "MAX" "claude"
[ -f "$TMP/run-meta.yaml" ] && pass "write_run_meta creates file" || fail "write_run_meta missing file"

# Test 2: read_meta_field extracts a known field
host=$(read_meta_field "$TMP/run-meta.yaml" host)
[ "$host" = "tk-mbp16-m3" ] && pass "read host" || fail "read host got '$host'"

tier=$(read_meta_field "$TMP/run-meta.yaml" tier)
[ "$tier" = "MAX" ] && pass "read tier" || fail "read tier got '$tier'"

# Test 3: write_kernel_meta serializes contributing_hosts list
write_kernel_meta "$TMP/kernel-meta.yaml" 2 23 "tk-mbp16-m3,h2ejvun"
grep -q "contributing_hosts:" "$TMP/kernel-meta.yaml" && pass "kernel meta has contributing_hosts" || fail "missing contributing_hosts"
grep -q "K_threshold: 2" "$TMP/kernel-meta.yaml" && pass "kernel meta has K_threshold" || fail "missing K_threshold"

# Test 6: read_meta_list extracts contributing_hosts list
hosts=$(read_meta_list "$TMP/kernel-meta.yaml" contributing_hosts)
[ "$(echo "$hosts" | wc -l | tr -d ' ')" = "2" ] && pass "read_meta_list count=2" \
    || fail "read_meta_list expected 2 lines got: $hosts"

# Test 7: read_meta_list items are correct
echo "$hosts" | grep -q "tk-mbp16-m3" && pass "read_meta_list has host1" \
    || fail "missing tk-mbp16-m3"
echo "$hosts" | grep -q "h2ejvun" && pass "read_meta_list has host2" \
    || fail "missing h2ejvun"

echo "==="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
