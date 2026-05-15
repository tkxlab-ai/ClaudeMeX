#!/usr/bin/env bash
# Test suite for Release/deploy.sh
# TDD verification: parameter validation, copy correctness, structure verification
# Usage: bash tests/test-b4-deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY="$PROJECT_ROOT/Release/deploy.sh"
TESTS_PASSED=0
TESTS_FAILED=0
TMP_BASE=""

# ── Helpers ──

green() { printf "\033[32mPASS\033[0m %s\n" "$1"; }
red()   { printf "\033[31mFAIL\033[0m %s\n" "$1"; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    green "$label"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    red "$label (expected=$expected, actual=$actual)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_file() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    green "$label"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    red "$label (file not found: $path)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_dir() {
  local label="$1" path="$2"
  if [ -d "$path" ]; then
    green "$label"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    red "$label (dir not found: $path)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_output_contains() {
  local label="$1" pattern="$2" output="$3"
  if echo "$output" | grep -Ei "$pattern"; then
    green "$label"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    red "$label (pattern not found: $pattern)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

run_expect_fail() {
  # Run command that should fail; returns 0 if it failed (exit!=0), 1 otherwise
  local output rc=0
  output=$("$@" 2>&1) || rc=$?
  echo "$output"
  return "$rc"
}

setup_mock_outputs() {
  TMP_BASE="$(mktemp -d)"
  local tier_dir
  for tier in MIN COMMON MAX; do
    tier_dir="$TMP_BASE/outputs/CLAUDE-CONF-${tier}-20260420"
    mkdir -p "$tier_dir/rules"
    echo "# CLAUDE.md $tier" > "$tier_dir/CLAUDE.md"
    echo "# Rule 1 for $tier" > "$tier_dir/rules/01-identity.md"
    echo "# Rule 2 for $tier" > "$tier_dir/rules/02-execution.md"
    echo "# Rule 3 for $tier" > "$tier_dir/rules/03-quality.md"
  done
  # Extra: older MIN directory (should be skipped in favor of newer)
  mkdir -p "$TMP_BASE/outputs/CLAUDE-CONF-MIN-20260301/rules"
  echo "# Old MIN CLAUDE.md" > "$TMP_BASE/outputs/CLAUDE-CONF-MIN-20260301/CLAUDE.md"
  echo "# Old rule" > "$TMP_BASE/outputs/CLAUDE-CONF-MIN-20260301/rules/01-test.md"
}

cleanup() {
  if [ -d "$TMP_BASE" ]; then
    rm -rf "$TMP_BASE"
  fi
  rm -rf /tmp/test-deploy-target-20260430
}

trap cleanup EXIT

# ── Tests ──

echo "=== T1: No parameters → exit 2 ==="
rc=0
output=$("$DEPLOY" 2>&1) || rc=$?
assert_eq "Exit code 2" "2" "$rc"
assert_output_contains "Shows usage" "usage|MIN|COMMON" "$output"

echo ""
echo "=== T2: Invalid tier → exit 2 ==="
mkdir -p /tmp/test-deploy-target-20260430
rc=0
output=$("$DEPLOY" WRONG /tmp/test-deploy-target-20260430 2>&1) || rc=$?
assert_eq "Exit code 2" "2" "$rc"
assert_output_contains "Rejects invalid tier" "error|invalid|must be" "$output"

echo ""
echo "=== T3: Empty tier → exit 2 ==="
rc=0
output=$("$DEPLOY" "" /tmp/test-deploy-target-20260430 2>&1) || rc=$?
assert_eq "Exit code 2" "2" "$rc"

echo ""
echo "=== T4: Missing target-dir → exit 2 ==="
rc=0
output=$("$DEPLOY" MIN 2>&1) || rc=$?
assert_eq "Exit code 2" "2" "$rc"

echo ""
# Now test with mock outputs
setup_mock_outputs

echo "=== T5: Deploy MIN tier to temp target ==="
TARGET="$TMP_BASE/target-min"
mkdir -p "$TARGET"
output=$("$DEPLOY" MIN "$TARGET" --base "$TMP_BASE/outputs" 2>&1)
rc=$?
assert_eq "Exit code 0" "0" "$rc"
assert_file "CLAUDE.md exists" "$TARGET/CLAUDE.md"
assert_dir "rules dir exists" "$TARGET/rules"

echo ""
echo "=== T6: Rules copied correctly ==="
count=$(find "$TARGET/rules" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "Rule count" "3" "$count"

echo ""
echo "=== T7: Deploy COMMON tier ==="
TARGET2="$TMP_BASE/target-common"
mkdir -p "$TARGET2"
output=$("$DEPLOY" COMMON "$TARGET2" --base "$TMP_BASE/outputs" 2>&1)
rc=$?
assert_eq "Exit code 0" "0" "$rc"
assert_file "CLAUDE.md exists" "$TARGET2/CLAUDE.md"
count=$(find "$TARGET2/rules" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "Rule count" "3" "$count"

echo ""
echo "=== T8: Deploy MAX tier ==="
TARGET3="$TMP_BASE/target-max"
mkdir -p "$TARGET3"
output=$("$DEPLOY" MAX "$TARGET3" --base "$TMP_BASE/outputs" 2>&1)
rc=$?
assert_eq "Exit code 0" "0" "$rc"

echo ""
echo "=== T9: Nonexistent outputs dir → exit 1 ==="
TARGET4="$TMP_BASE/target-fail"
mkdir -p "$TARGET4"
rc=0
"$DEPLOY" MIN "$TARGET4" --base /nonexistent/path/404 2>&1 || rc=$?
assert_eq "Fails with exit 1" "1" "$rc"

echo ""
echo "=== T10: CLAUDE.md content matches tier ==="
content=$(cat "$TARGET/CLAUDE.md" 2>/dev/null)
if echo "$content" | grep -q "MIN"; then
  green "CLAUDE.md contains correct tier label"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  red "CLAUDE.md does not contain expected content"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "=== T11: Selects latest tier directory ==="
# Setup: create a newer MIN directory
mkdir -p "$TMP_BASE/outputs/CLAUDE-CONF-MIN-20260501/rules"
echo "# Newest MIN CLAUDE.md" > "$TMP_BASE/outputs/CLAUDE-CONF-MIN-20260501/CLAUDE.md"
echo "# Newest rule" > "$TMP_BASE/outputs/CLAUDE-CONF-MIN-20260501/rules/01-new.md"
TARGET6="$TMP_BASE/target-latest"
mkdir -p "$TARGET6"
"$DEPLOY" MIN "$TARGET6" --base "$TMP_BASE/outputs" >/dev/null 2>&1
content=$(cat "$TARGET6/CLAUDE.md" 2>/dev/null)
if echo "$content" | grep -q "Newest"; then
  green "Selects latest tier directory"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  red "Did not select latest tier directory"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "=== T12: Success output lists deployed files ==="
TARGET5="$TMP_BASE/target-output"
mkdir -p "$TARGET5"
output=$("$DEPLOY" MIN "$TARGET5" --base "$TMP_BASE/outputs" 2>&1)
if echo "$output" | grep -Ei "deploy|\.md"; then
  green "Success output mentions deployed files"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  red "Success output missing file listing"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ── Summary ──
echo ""
echo "==============================="
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "==============================="

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
