#!/usr/bin/env bash
PASS=0; FAIL=0; TESTS_RUN=0
pass() { PASS=$((PASS+1)); TESTS_RUN=$((TESTS_RUN+1)); echo "✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); TESTS_RUN=$((TESTS_RUN+1)); echo "❌ FAIL: $1"; }
trap 'rm -f /tmp/ipv4_test.txt' EXIT

echo "=== TDD-P1-Remaining: Copyright, IPv4, LMATCHES trap ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "--- P1-C1: Copyright consistency ---"
count=$(grep -rl 'Claude Code Config Generator contributors' "$BASE/" --include="*.md" 2>/dev/null | grep -v 'reviews/' | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then pass "No contributors copyright mismatch"; else fail "$count files still say contributors"; fi

count2=$({ grep -l 'Copyright.*TKXLAB.AI' "$BASE/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md" 2>/dev/null; grep -rl 'Copyright.*TKXLAB.AI' "$BASE/Release/v1.0.0/" "$BASE/Release/v1.0.1/" --include="*.md" 2>/dev/null; } | sort | uniq | wc -l | tr -d ' ')
if [ "$count2" -ge 4 ]; then pass "$count2 files have correct TKXLAB copyright"; else fail "Only $count2 files have correct copyright"; fi

echo "--- P1-C2: IPv4 filter works ---"
printf 'Internal: 192.168.1.100 10.0.0.1 172.16.0.1 127.0.0.1\nPublic: 8.8.8.8 198.51.100.52\n' > /tmp/ipv4_test.txt
result=$(bash "$BASE/Release/redact-scan.sh" /tmp/ipv4_test.txt 2>/dev/null || true)
if echo "$result" | grep -q '192.168\|10.0.0\|172.16\|127.0'; then
  fail "IPv4 RFC1918 loopback still match"
else
  pass "IPv4 RFC1918 loopback excluded"
fi

echo "--- P1-C3: LMATCHES trap ---"
if grep -q "trap.*LMATCHES" "$BASE/Release/redact-scan.sh" 2>/dev/null && grep -q 'LMATCHES=.*mktemp' "$BASE/Release/redact-scan.sh" 2>/dev/null; then
  pass "LMATCHES trap mktemp both exist"
else
  fail "LMATCHES trap or mktemp missing"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ($TESTS_RUN tests) ==="
if [ "$FAIL" -gt 0 ]; then exit 1; else exit 0; fi
