#!/usr/bin/env bash
# Smoke test for claudemex merge — flag handling + early-exit cases
set -uo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SELF_DIR/.." && pwd)"
MERGE="$PROJECT_ROOT/scripts/merge.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

# Test 1: --help prints synopsis
out=$("$MERGE" --help 2>&1 || true)
echo "$out" | grep -q "claudemex merge" && pass "--help works" || fail "no --help: $out"

# Test 2: empty outputs/ → exit 1
TMP=$(mktemp -d); trap "rm -rf '$TMP'" EXIT
out=$("$MERGE" --from="$TMP" --allow-untrusted-hosts 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "empty input → exit 1" || fail "empty: rc=$rc out=$out"

# Test 3: N=1 → exit 1
mkdir -p "$TMP/host-a-20260505/rules"
cat > "$TMP/host-a-20260505/run-meta.yaml" <<EOF
host: host-a
generator_version: v1.1.0
tier: MAX
generated_at: 2026-05-05T07:35Z
tool: claude
EOF
echo "# stub" > "$TMP/host-a-20260505/rules/01-identity.md"
out=$("$MERGE" --from="$TMP" --allow-untrusted-hosts 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "N=1 → exit 1" || fail "N=1: rc=$rc out=$out"

# Test 4: --from missing dir → exit 1
out=$("$MERGE" --from=/nonexistent/path 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "missing --from dir → exit 1" || fail "missing dir: rc=$rc"

# Test 5: unknown flag → exit 2
out=$("$MERGE" --bogus-flag 2>&1) && rc=0 || rc=$?
[ "$rc" = "2" ] && pass "unknown flag → exit 2" || fail "unknown flag: rc=$rc"

# --- Hardening tests (Codex review followups) ---------------------------------

# Test 6: --week injection → reject (don't let it flow into rm -rf)
out=$("$MERGE" --from="$TMP" --week=../../foo 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "--week=../../foo → exit 1 (path-injection guard)" || fail "week injection: rc=$rc"

# Test 7: --week with bad format
out=$("$MERGE" --from="$TMP" --week=2026 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "--week=2026 (no Wxx) → exit 1" || fail "bad week format: rc=$rc"

# Test 8: --threshold non-numeric → reject
out=$("$MERGE" --from="$TMP" --threshold=abc 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "--threshold=abc → exit 1" || fail "threshold=abc: rc=$rc"

# Test 9: --threshold=0 → reject
out=$("$MERGE" --from="$TMP" --threshold=0 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "--threshold=0 → exit 1" || fail "threshold=0: rc=$rc"

# Test 10: --threshold negative → reject
out=$("$MERGE" --from="$TMP" --threshold=-1 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "--threshold=-1 → exit 1" || fail "threshold=-1: rc=$rc"

# Test 11: same host with two runs → only the latest counts as one vote.
# Stage host-a's existing run plus an older run; expect N=1 (still exits 1
# because we have only one effective host), not N=2.
mkdir -p "$TMP/host-a-20260101/rules"
cat > "$TMP/host-a-20260101/run-meta.yaml" <<EOF
host: host-a
generator_version: v1.0.6
tier: MAX
generated_at: 2026-01-01T00:00Z
tool: claude
EOF
echo "# old stub" > "$TMP/host-a-20260101/rules/01-identity.md"
out=$("$MERGE" --from="$TMP" --allow-untrusted-hosts 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && echo "$out" | grep -q "N=1" && pass "duplicate-host runs collapse to N=1" \
    || fail "duplicate-host: rc=$rc out=$out"

# --- Adversarial tests (Codex red-team C1/C2/A2/C3/E1) -----------------------
# Each test stages a malicious input and expects the merge to either reject
# the directory entirely (filtering it out of host discovery) or refuse to
# accept the bad value.

ADV=$(mktemp -d); trap "rm -rf '$ADV' '$TMP'" EXIT

# Stage a clean baseline of two real hosts so we can attempt to add
# a malicious host alongside them without tripping N<2.
for h in alpha beta; do
    mkdir -p "$ADV/${h}-20260506/rules"
    cat > "$ADV/${h}-20260506/run-meta.yaml" <<EOF
host: $h
tier: MAX
generator_version: v1.1.0
EOF
    printf '# 01\n## Section\n\nbody.\n' > "$ADV/${h}-20260506/rules/01-identity.md"
done

# Test 12 (C1/C2): dir name does NOT match "<host>-<YYYYMMDD>" pattern
# → should be rejected. Stage evil-20260506/ with run-meta.yaml saying
# host: alpha (claiming to be alpha but dir name says evil).
mkdir -p "$ADV/evil-20260506/rules"
cat > "$ADV/evil-20260506/run-meta.yaml" <<EOF
host: alpha
tier: MAX
generator_version: v1.1.0
EOF
echo "# pwn" > "$ADV/evil-20260506/rules/01-identity.md"
out=$("$MERGE" --from="$ADV" --week=2026-W19 --allow-untrusted-hosts 2>&1) && rc=0 || rc=$?
echo "$out" | grep -qE "rejected.*directory|does not match.*<host>-<YYYYMMDD>" \
    && pass "C1/C2: dir name vs host field mismatch → rejected" \
    || fail "C1/C2: spoofed host accepted: rc=$rc out=$out"
rm -rf "$ADV/evil-20260506"

# Test 13 (A2): host: with shell metas / path traversal → rejected by
# the strict hostname regex
mkdir -p "$ADV/../../tmp-test-13/rules" 2>/dev/null
mkdir -p "$ADV/badhost-20260506/rules"
cat > "$ADV/badhost-20260506/run-meta.yaml" <<EOF
host: ../../../etc/pwn
tier: MAX
generator_version: v1.1.0
EOF
echo "# pwn" > "$ADV/badhost-20260506/rules/01-identity.md"
out=$("$MERGE" --from="$ADV" --week=2026-W19 --allow-untrusted-hosts 2>&1) && rc=0 || rc=$?
echo "$out" | grep -q "is not a valid hostname" \
    && pass "A2: host field with path traversal → rejected" \
    || fail "A2: bad host accepted: rc=$rc out=$out"
rm -rf "$ADV/badhost-20260506"

# Test 14 (C3): --threshold=1 explicit override → rejected
out=$("$MERGE" --from="$TMP" --threshold=1 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && echo "$out" | grep -q "must be >= 2" \
    && pass "C3: --threshold=1 → exit 1 (single-host quorum unsafe)" \
    || fail "C3: threshold=1 accepted: rc=$rc out=$out"

# Test 15 (E1): future-dated dir like gamma-20991231/ → rejected
mkdir -p "$ADV/gamma-20991231/rules"
cat > "$ADV/gamma-20991231/run-meta.yaml" <<EOF
host: gamma
tier: MAX
generator_version: v1.1.0
EOF
echo "# future" > "$ADV/gamma-20991231/rules/01-identity.md"
out=$("$MERGE" --from="$ADV" --week=2026-W19 --allow-untrusted-hosts 2>&1) && rc=0 || rc=$?
echo "$out" | grep -q "is in the future" \
    && pass "E1: future-dated dir → rejected" \
    || fail "E1: future-dated dir accepted: rc=$rc out=$out"
rm -rf "$ADV/gamma-20991231"

# Test 16 (Codex C1/C2 deeper): without a whitelist source AND without
# --allow-untrusted-hosts, merge must refuse to run. (This is the deeper fix
# for the fake-host-quorum attack: even internally-consistent fake host
# dirs can't reach quorum if the user must pre-declare the trusted set.)
out=$(CLAUDEMEX_TRUSTED_HOSTS=/nonexistent/path "$MERGE" --from="$ADV" --week=2026-W19 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && echo "$out" | grep -q "no trusted-host whitelist" \
    && pass "no whitelist + no opt-out → exit 1 (deeper C1/C2 fix)" \
    || fail "no whitelist accepted: rc=$rc out=$out"

# Test 17 (whitelist enforcement): --hosts=alpha,beta with a fake third
# host present → fake host is filtered out as 'not in trust whitelist'.
mkdir -p "$ADV/fakehost-20260506/rules"
cat > "$ADV/fakehost-20260506/run-meta.yaml" <<EOF
host: fakehost
tier: MAX
generator_version: v1.1.0
EOF
printf '# 01\n## Pwned\n\nattacker payload.\n' > "$ADV/fakehost-20260506/rules/01-identity.md"
out=$("$MERGE" --from="$ADV" --week=2026-W19 --hosts=alpha,beta 2>&1) && rc=0 || rc=$?
echo "$out" | grep -q "fakehost.*not in trust whitelist" \
    && pass "C1/C2 deeper: --hosts=alpha,beta excludes fakehost from vote" \
    || fail "whitelist did not exclude fakehost: rc=$rc out=$out"
# Verify common-kernel does NOT contain the attacker payload
ls "merged/2026-W19/common-kernel/rules/01-identity.md" 2>/dev/null \
    && grep -q "Pwned" "merged/2026-W19/common-kernel/rules/01-identity.md" \
    && fail "attacker payload leaked into common-kernel!" \
    || pass "attacker payload NOT in common-kernel (whitelist held)"
rm -rf "$ADV/fakehost-20260506" merged/

# Test 18 (Codex stop-time): --allow-untrusted-hosts + --hosts are mutually
# exclusive. Previously the former silently disabled the latter, letting an
# attacker who could inject the opt-out flag bypass an explicit whitelist.
out=$("$MERGE" --from="$ADV" --week=2026-W19 --hosts=alpha,beta --allow-untrusted-hosts 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && echo "$out" | grep -q "mutually exclusive" \
    && pass "--hosts + --allow-untrusted-hosts → exit 1 (mutually exclusive)" \
    || fail "mutex flag combo accepted: rc=$rc out=$out"

# Test 19 (Codex round-2 A1): trusted-hosts file MUST NOT be a symlink.
TRUST_DIR=$(mktemp -d)
ln -s /etc/passwd "$TRUST_DIR/trusted-hosts"
out=$(CLAUDEMEX_TRUSTED_HOSTS="$TRUST_DIR/trusted-hosts" "$MERGE" --from="$ADV" --week=2026-W19 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && echo "$out" | grep -q "is a symlink" \
    && pass "A1: trusted-hosts symlink → exit 1" \
    || fail "A1: trusted-hosts symlink accepted: rc=$rc out=$out"
rm -rf "$TRUST_DIR"

# Test 20 (Codex round-2 B1/B2): two trusted hosts with byte-identical
# rules/ trees → SECURITY warning is emitted (clone-detection mitigation).
# The two existing alpha/beta dirs in $ADV already have identical layouts,
# but their content differs (different host: in run-meta.yaml). Re-stage
# them with TRULY identical rules/ to trigger the warn.
mkdir -p "$ADV/clone-a-20260506/rules" "$ADV/clone-b-20260506/rules"
cat > "$ADV/clone-a-20260506/run-meta.yaml" <<EOF
host: clone-a
tier: MAX
generator_version: v1.1.0
EOF
cat > "$ADV/clone-b-20260506/run-meta.yaml" <<EOF
host: clone-b
tier: MAX
generator_version: v1.1.0
EOF
printf '# 01\n## Section\n\nidentical body across both hosts.\n' > "$ADV/clone-a-20260506/rules/01-identity.md"
cp "$ADV/clone-a-20260506/rules/01-identity.md" "$ADV/clone-b-20260506/rules/01-identity.md"
out=$("$MERGE" --from="$ADV" --week=2026-W19 --hosts=clone-a,clone-b 2>&1) && rc=0 || rc=$?
echo "$out" | grep -qE "byte-identical rules/ trees" \
    && pass "B1/B2: clone-tree detection warns on identical rules/ trees" \
    || fail "B1/B2: no clone warning: rc=$rc out=$out"
rm -rf "$ADV/clone-a-20260506" "$ADV/clone-b-20260506" merged/

# Test 21 (Codex round-2 D3): --max-bytes > 10 GiB cap → reject
out=$(IMPORT="$PROJECT_ROOT/scripts/import.sh"; bash "$IMPORT" --max-bytes=99999999999 --into=/tmp/dummy /nonexistent.tar.gz 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && echo "$out" | grep -qE "exceeds ceiling.*10 GiB" \
    && pass "D3: --max-bytes > 10 GiB → exit 1" \
    || fail "D3: huge max-bytes accepted: rc=$rc out=$out"

# Test 22 (Codex stop-time): oversized integer (>19 digits) MUST be rejected.
# Earlier code only ran [ X -gt CEILING ] which bash silently truncates and
# emits an "integer expected" warning (without -e, execution continues) —
# the ceiling check became inert. Length-cap-first defence catches this.
IMPORT_BIN="$PROJECT_ROOT/scripts/import.sh"
out=$(bash "$IMPORT_BIN" --max-bytes=99999999999999999999 --into=/tmp/dummy /nonexistent.tar.gz 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && echo "$out" | grep -qE "too many digits|exceeds ceiling" \
    && pass "D3: 20-digit --max-bytes (overflow attempt) → exit 1" \
    || fail "D3: 20-digit max-bytes bypassed ceiling: rc=$rc out=$out"

echo "==="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
