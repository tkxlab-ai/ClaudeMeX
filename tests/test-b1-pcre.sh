#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# TDD test for B1: PCRE compatibility on macOS (BSD grep)
# RED gate: proves grep -nP fails → must fix → must pass after fix
# -----------------------------------------------------------------------------
set -e
PASS=0
FAIL=0
SKIPPED=0
TESTS_RUN=0

pass() { PASS=$((PASS + 1)); TESTS_RUN=$((TESTS_RUN + 1)); echo "✅ PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TESTS_RUN=$((TESTS_RUN + 1)); echo "❌ FAIL: $1"; }
skip() { SKIPPED=$((SKIPPED + 1)); echo "⏭ SKIP: $1"; }

echo "=== TDD-B1: PCRE macOS Compatibility Tests ==="
echo

TMPD=$(mktemp -d)
SCANNED_FILE="${TMPD}/test-input.md"
EXIT_CODE=0

# -----------------------------------------------------------------------------
# Test 1: redact-scan.sh runs without syntax error (bash -n)
# -----------------------------------------------------------------------------
echo "--- Test 1: Syntax validation ---"
if bash -n Release/redact-scan.sh; then
  pass "redact-scan.sh syntax OK"
else
  fail "redact-scan.sh has syntax errors (bash -n)"
fi

# -----------------------------------------------------------------------------
# Test 2: Clean scan of safe file succeeds (exit 0)
# -----------------------------------------------------------------------------
echo "--- Test 2: Clean content scan ---"
echo "This is a clean doc with no personal info." > "$SCANNED_FILE"
EXIT_CODE=0
bash Release/redact-scan.sh "$SCANNED_FILE" > "${TMPD}/out.txt" 2>&1 || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
  pass "Clean file exits 0"
else
  fail "Clean file exits $EXIT_CODE (expected 0)"
fi

# -----------------------------------------------------------------------------
# Test 3: Email detection works WITHOUT PCRE (BSD grep compatible)
# -----------------------------------------------------------------------------
echo "--- Test 3: Email pattern (BSD grep compatible) ---"
echo "Contact user@notexample.com for help." > "$SCANNED_FILE"
EXIT_CODE=0
bash Release/redact-scan.sh "$SCANNED_FILE" > "${TMPD}/out.txt" 2>&1 || EXIT_CODE=$?
OUTPUT=$(cat "${TMPD}/out.txt")
if grep -q '\[BLOCK\]' "$TMPD/out.txt" 2>/dev/null; then
  pass "Email detected: personal email triggers [BLOCK]"
else
  fail "Email NOT detected — PCRE pattern may have failed on macOS"
fi

# -----------------------------------------------------------------------------
# Test 4: Example emails do NOT trigger (should pass)
# -----------------------------------------------------------------------------
echo "--- Test 4: Safe emails — example.com/test.com ---"
echo "Contact user@example.com or admin@test.com." > "$SCANNED_FILE"
EXIT_CODE=0
bash Release/redact-scan.sh "$SCANNED_FILE" > "${TMPD}/out.txt" 2>&1 || EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
  pass "Example emails correctly ignored"
else
  fail "Example emails incorrectly flagged"
fi

# -----------------------------------------------------------------------------
# Test 5: Email regex does NOT use grep -P (PCRE) internally
# -----------------------------------------------------------------------------
echo "--- Test 5: No grep -P in scan_category calls ---"
if grep -n 'scan_category.*-P\|-- -P\|"-P"' Release/redact-scan.sh >/dev/null 2>&1; then
  fail "grep -P found in scan_category — will fail on macOS"
else
  # Check if -nP is still used (it uses PCRE lookahead)
  if grep -nE "email.*-nP|Personal.*-nP" Release/redact-scan.sh >/dev/null 2>&1; then
    fail "Email line uses -nP (PCRE negative lookahead breaks on macOS)"
  else
    pass "No grep -P in email category — BSD compatible"
  fi
fi

# -----------------------------------------------------------------------------
# Test 6: Detect real personal email (real domain, not example)
# -----------------------------------------------------------------------------
echo "--- Test 6: Real personal email detection ---"
echo "Email john.doe@gmail.com or jane@company.org" > "$SCANNED_FILE"
EXIT_CODE=0
bash Release/redact-scan.sh "$SCANNED_FILE" > "${TMPD}/out.txt" 2>&1 || EXIT_CODE=$?
if grep -q '\[BLOCK\]' "$TMPD/out.txt" 2>/dev/null; then
  pass "Real personal emails detected"
else
  fail "Real personal emails missed"
fi

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
rm -rf "$TMPD"

echo
echo "=== Results: $PASS passed, $FAIL failed, $SKIPPED skipped ($TESTS_RUN tests) ==="
echo
if [ "$FAIL" -gt 0 ]; then
  echo "🔴 RED gate active — TDD cycle not complete. Fix required."
  exit 1
else
  echo "🟢 All tests green."
  exit 0
fi
