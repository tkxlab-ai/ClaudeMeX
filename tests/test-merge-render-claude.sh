#!/usr/bin/env bash
# Unit test: lib/render-claude.sh
set -uo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SELF_DIR/.." && pwd)"
LIB="$PROJECT_ROOT/scripts/lib/render-claude.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

# shellcheck source=/dev/null
. "$LIB"

TMP=$(mktemp -d); trap "rm -rf '$TMP'" EXIT
mkdir -p "$TMP/kernel/common-kernel/rules" \
         "$TMP/kernel/per-machine-extension/host-a/rules"

echo "# 01 ident" > "$TMP/kernel/common-kernel/rules/01-identity.md"
echo "# 02 exec"  > "$TMP/kernel/common-kernel/rules/02-execution.md"
echo "# 11 host-a project" > "$TMP/kernel/per-machine-extension/host-a/rules/11-host-a-proj.md"

OUT="$TMP/CLAUDE.md"
render_claude_md "$TMP/kernel" "host-a" "$OUT"

# Test 1: output exists
[ -f "$OUT" ] && pass "render produces output" || fail "no output"

# Test 2: contains common content
grep -q "01 ident" "$OUT" && pass "common 01 included" || fail "missing 01"
grep -q "02 exec" "$OUT" && pass "common 02 included" || fail "missing 02"

# Test 3: contains host extension
grep -q "11 host-a project" "$OUT" && pass "extension included" || fail "missing extension"

# Test 4: order — common before extension
COMMON_LINE=$(grep -n "01 ident" "$OUT" | head -1 | cut -d: -f1)
EXT_LINE=$(grep -n "11 host-a" "$OUT" | head -1 | cut -d: -f1)
[ "$COMMON_LINE" -lt "$EXT_LINE" ] && pass "common before extension" \
    || fail "ordering wrong: common@$COMMON_LINE extension@$EXT_LINE"

# Test 5: missing host extension dir is OK (host that didn't contribute uses common only)
OUT2="$TMP/CLAUDE2.md"
render_claude_md "$TMP/kernel" "host-without-extension" "$OUT2"
[ -f "$OUT2" ] && grep -q "01 ident" "$OUT2" && pass "host with no ext: common-only render" \
    || fail "host with no ext failed"

# Test 6: missing common-kernel dir is an error
mkdir -p "$TMP/empty"
err=$(render_claude_md "$TMP/empty" "host-a" "$TMP/CLAUDE3.md" 2>&1) && rc=0 || rc=$?
[ "$rc" != "0" ] && pass "missing common-kernel → non-zero exit" \
    || fail "should error on missing common-kernel"

echo "==="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
