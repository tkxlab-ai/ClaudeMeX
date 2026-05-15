#!/usr/bin/env bash
# E2E test for claudemex merge — runs against three fixture scenarios:
#   - two-hosts-aligned   : everything common, drift empty
#   - two-hosts-drift     : 01 common, 13 in extension on both
#   - three-hosts-mixed   : 01 common, 13 common (alpha+beta majority), gamma in drift
set -uo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SELF_DIR/.." && pwd)"
MERGE="$PROJECT_ROOT/scripts/merge.sh"
FIXTURES="$SELF_DIR/fixtures/merge"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

# Each scenario runs in its own tmp workspace to keep merge outputs isolated.
run_merge() {
    # Args: scenario_dir, week, threshold
    local scenario="$1" week="$2" k="$3"
    local TMP
    TMP=$(mktemp -d)
    cp -R "$FIXTURES/$scenario" "$TMP/outputs"
    ( cd "$TMP" && "$MERGE" --from=outputs --week="$week" --threshold="$k" --allow-untrusted-hosts >/dev/null 2>&1 )
    local rc=$?
    echo "$TMP|$rc"
}

check_dir_empty() { [ -z "$(ls -A "$1" 2>/dev/null)" ]; }

# ───────────────────── Scenario 1: two-hosts-aligned ─────────────────────
res=$(run_merge two-hosts-aligned 2026-W18 2)
TMP="${res%|*}"; rc="${res#*|}"
[ "$rc" = "0" ] && pass "aligned: merge exits 0" || fail "aligned: rc=$rc"
[ -f "$TMP/merged/2026-W18/common-kernel/rules/01-identity.md" ] && pass "aligned: 01 in common" || fail "aligned: no 01 in common"
[ -f "$TMP/merged/2026-W18/common-kernel/rules/02-execution.md" ] && pass "aligned: 02 in common" || fail "aligned: no 02 in common"
check_dir_empty "$TMP/merged/2026-W18/per-machine-extension/alpha/rules" && pass "aligned: alpha ext empty" || fail "aligned: alpha ext not empty"
check_dir_empty "$TMP/merged/2026-W18/per-machine-extension/beta/rules" && pass "aligned: beta ext empty" || fail "aligned: beta ext not empty"
grep -q '\*No drift detected\.\*' "$TMP/merged/2026-W18/drift-report.md" && pass "aligned: drift report empty" || fail "aligned: drift unexpectedly populated"
rm -rf "$TMP"

# ───────────────────── Scenario 2: two-hosts-drift ─────────────────────
res=$(run_merge two-hosts-drift 2026-W18 2)
TMP="${res%|*}"; rc="${res#*|}"
[ "$rc" = "0" ] && pass "drift: merge exits 0" || fail "drift: rc=$rc"
[ -f "$TMP/merged/2026-W18/common-kernel/rules/01-identity.md" ] && pass "drift: 01 in common" || fail "drift: 01 missing"
[ ! -f "$TMP/merged/2026-W18/common-kernel/rules/13-tools.md" ] && pass "drift: 13 NOT in common" || fail "drift: 13 leaked into common"
[ -f "$TMP/merged/2026-W18/per-machine-extension/alpha/rules/13-tools.md" ] && pass "drift: 13 in alpha ext" || fail "drift: 13 not in alpha ext"
[ -f "$TMP/merged/2026-W18/per-machine-extension/beta/rules/13-tools.md" ] && pass "drift: 13 in beta ext" || fail "drift: 13 not in beta ext"
grep -q 'rules/13-tools.md' "$TMP/merged/2026-W18/drift-report.md" && pass "drift: drift-report mentions 13-tools" || fail "drift: drift-report missing 13-tools"
rm -rf "$TMP"

# ───────────────────── Scenario 3: three-hosts-mixed ─────────────────────
res=$(run_merge three-hosts-mixed 2026-W18 2)
TMP="${res%|*}"; rc="${res#*|}"
[ "$rc" = "0" ] && pass "mixed: merge exits 0" || fail "mixed: rc=$rc"
[ -f "$TMP/merged/2026-W18/common-kernel/rules/01-identity.md" ] && pass "mixed: 01 in common" || fail "mixed: 01 missing"
[ -f "$TMP/merged/2026-W18/common-kernel/rules/13-tools.md" ] && pass "mixed: 13 common (alpha+beta majority)" || fail "mixed: 13 not common"
[ ! -f "$TMP/merged/2026-W18/per-machine-extension/alpha/rules/13-tools.md" ] && pass "mixed: alpha 13 not in ext (it's majority)" || fail "mixed: alpha 13 in ext"
[ -f "$TMP/merged/2026-W18/per-machine-extension/gamma/rules/13-tools.md" ] && pass "mixed: gamma 13 in ext (minority)" || fail "mixed: gamma 13 not in ext"
grep -q 'gamma' "$TMP/merged/2026-W18/drift-report.md" && pass "mixed: drift-report mentions gamma" || fail "mixed: no gamma in drift"
# kernel-meta should record 3 contributing hosts
grep -qE '^\s*- alpha' "$TMP/merged/2026-W18/common-kernel/kernel-meta.yaml" && pass "mixed: kernel-meta lists alpha" || fail "mixed: kernel-meta missing alpha"
grep -qE '^\s*- gamma' "$TMP/merged/2026-W18/common-kernel/kernel-meta.yaml" && pass "mixed: kernel-meta lists gamma" || fail "mixed: kernel-meta missing gamma"
# Enriched drift report: Summary + Details sections, per-host short hash table
grep -q '^## Summary' "$TMP/merged/2026-W18/drift-report.md" && pass "mixed: drift-report has Summary section" || fail "mixed: drift-report missing Summary section"
grep -q '^## Details' "$TMP/merged/2026-W18/drift-report.md" && pass "mixed: drift-report has Details section" || fail "mixed: drift-report missing Details section"
grep -qE '\| Host \| Short hash \| Lines \| Note \|' "$TMP/merged/2026-W18/drift-report.md" && pass "mixed: drift-report Details has per-host table" || fail "mixed: drift-report missing per-host table"
grep -q 'majority' "$TMP/merged/2026-W18/drift-report.md" && pass "mixed: drift-report marks majority hosts" || fail "mixed: drift-report missing majority marker"
# BUG #7 regression: sections that fully agree must NOT appear in drift
grep -q '01-identity.md' "$TMP/merged/2026-W18/drift-report.md" && fail "mixed: 01-identity (fully agreed) leaked into drift" || pass "mixed: fully-agreed 01-identity NOT in drift"
rm -rf "$TMP"

echo "==="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
