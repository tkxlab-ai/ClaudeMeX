#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# TDD test for P1 fixes:
# 1. LMATCHES trap in redact-scan.sh
# 2. test-b2-categories.sh trap
# 3. Category sequential numbering (1–15, .env at end)
# 4. IPv4 private IP exclusion (RFC 1918 + loopback)
#
# Usage: bash tests/test-p1-fixes.sh
# Three-pass verification: run this file 3 times, all must be green.
# -----------------------------------------------------------------------------
set -e
PASS=0
FAIL=0
TESTS_RUN=0

pass() { PASS=$((PASS + 1)); TESTS_RUN=$((TESTS_RUN + 1)); echo "✅ PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TESTS_RUN=$((TESTS_RUN + 1)); echo "❌ FAIL: $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REDACT="$PROJECT_ROOT/Release/redact-scan.sh"

echo "=== TDD-P1: Fix Verification Tests ==="
echo

# =============================================================================
# Fix 1: trap 'rm -f "$LMATCHES"' EXIT in redact-scan.sh
# =============================================================================
echo "--- Fix 1: LMATCHES trap ---"
if grep -qF 'rm -f "$LMATCHES"' "$REDACT"; then
  pass "redact-scan.sh has LMATCHES cleanup"
else
  fail "redact-scan.sh missing LMATCHES cleanup"
fi
if grep -qE 'trap.*LMATCHES' "$REDACT" 2>/dev/null; then
  pass "redact-scan.sh has LMATCHES in trap"
else
  fail "redact-scan.sh LMATCHES not in active trap"
fi

# =============================================================================
# Fix 2: test-b2-categories.sh has trap
# =============================================================================
echo "--- Fix 2: test-b2 trap ---"
if grep -qE "trap.*TMPD.*EXIT" "$PROJECT_ROOT/tests/test-b2-categories.sh"; then
  pass "test-b2-categories.sh has TMPD EXIT trap"
else
  fail "test-b2-categories.sh missing TMPD EXIT trap"
fi

# =============================================================================
# Fix 3: Category sequential numbering (1–15)
# =============================================================================
echo "--- Fix 3: Category numbering ---"
CATEGORIES=$(grep -oE '# Category [0-9]+' "$REDACT" | grep -oE '[0-9]+' | head -15)
EXPECTED="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15"
ACTUAL=$(echo "$CATEGORIES" | tr '\n' ' ' | sed 's/ $//')
if [ "$ACTUAL" = "$EXPECTED" ]; then
  pass "Categories sequential 1–15"
else
  fail "Category gap detected: got '$ACTUAL'"
fi
# Verify .env is at the end (Category 15)
ENV_CAT=$(grep -n 'Category 15' "$REDACT" | tail -1)
if echo "$ENV_CAT" | grep -qi 'env'; then
  pass ".env reverse leak is Category 15 (last)"
else
  fail ".env not positioned as Category 15"
fi

# =============================================================================
# Fix 4: IPv4 private IP exclusion
# =============================================================================
echo "--- Fix 4: IPv4 private IP exclusion ---"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

# Test file with ONLY private IPs — should NOT flag
cat > "$TMPD/only-private.txt" << 'EOF'
Server IP: 10.0.1.50
Gateway: 192.168.1.1
Internal: 172.16.0.100
Another: 172.31.255.1
Loopback: 127.0.0.1
Docker bridge: 192.168.0.1
EOF

OUTPUT=$(bash "$REDACT" "$TMPD/only-private.txt" 2>&1 || true)
if echo "$OUTPUT" | grep -q '\[BLOCK\].*IPv4'; then
  fail "Private IPs incorrectly flagged as public"
else
  pass "Private IPs not flagged (correct)"
fi

# Test file with ONLY public IPs — should flag
cat > "$TMPD/only-public.txt" << 'EOF'
DNS: 8.8.8.8
Cloudflare: 1.1.1.1
VPS: 198.51.100.52
AWS: 54.239.28.85
EOF

OUTPUT=$(bash "$REDACT" "$TMPD/only-public.txt" 2>&1 || true)
if echo "$OUTPUT" | grep -q '\[BLOCK\].*IPv4'; then
  pass "Public IPs detected as expected"
else
  fail "Public IPs not detected"
fi

# Test file with MIXED private+public — only public should flag
cat > "$TMPD/mixed.txt" << 'EOF'
Internal server: 192.168.1.100
Public DNS: 8.8.4.4
Localhost: 127.0.0.1
CDN: 104.16.132.229
EOF

OUTPUT=$(bash "$REDACT" "$TMPD/mixed.txt" 2>&1 || true)
if echo "$OUTPUT" | grep -q '8.8.4.4' && echo "$OUTPUT" | grep -q '104.16.132.229'; then
  # Verify private IPs are NOT in the block output
  if ! echo "$OUTPUT" | grep -q '192\.168\.1\.100'; then
    pass "Mixed: public flagged, private excluded"
  else
    fail "Mixed: private IP (192.168.1.100) incorrectly flagged"
  fi
else
  fail "Mixed: missing public IPs in output"
fi

rm -rf "$TMPD"

echo
echo "=== Results: $PASS passed, $FAIL failed ($TESTS_RUN tests) ==="
echo
if [ "$FAIL" -gt 0 ]; then
  echo "🔴 RED gate active — P1 fixes not verified. Fix required."
  exit 1
else
  echo "🟢 All P1 fixes verified."
  exit 0
fi
