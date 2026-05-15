#!/usr/bin/env bash
# tests/test-audit-bdd.sh
# BDD scenarios for v1.0.2 post-audit fixes.
# Each scenario follows Given / When / Then.
#
# Usage:  bash tests/test-audit-bdd.sh
# Exit:   0 = all scenarios pass, 1 = any failure

set -u

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
FAIL_NAMES=()

red()   { printf '\033[0;31m%s\033[0m' "$*"; }
green() { printf '\033[0;32m%s\033[0m' "$*"; }
blue()  { printf '\033[0;34m%s\033[0m' "$*"; }

scenario() {
  local name="$1"
  local fn="$2"
  printf '%s ' "$(blue "Scenario:")"
  printf '%s ... ' "$name"
  if "$fn"; then
    printf '%s\n' "$(green PASS)"
    PASS=$((PASS + 1))
  else
    printf '%s\n' "$(red FAIL)"
    FAIL=$((FAIL + 1))
    FAIL_NAMES+=("$name")
  fi
}

# -----------------------------------------------------------------------------
# C1 — redact-scan must catch leaks inside review/ subdirectories
# -----------------------------------------------------------------------------
c1_review_subdir_leak_caught() {
  # Given a temp tree containing "ProjectAlpha" inside a review/ subdirectory
  local tmp
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" RETURN
  mkdir -p "$tmp/some-package/review"
  printf 'Reviewer note: ProjectBeta pulls from ProjectAlpha nightly\n' \
    > "$tmp/some-package/review/reviewer-notes.md"

  # When the scan runs against that tree
  local rc
  bash "$PROJECT_ROOT/Release/redact-scan.sh" "$tmp" >/dev/null 2>&1
  rc=$?

  # Then the scanner must block (non-zero exit, codename detected)
  [ "$rc" -ne 0 ]
}

# -----------------------------------------------------------------------------
# I4 — redact-scan invoked at repo root must catch leaks in arbitrary tracked files
# (covered indirectly by C1 since it scans a directory tree;
#  this scenario asserts the script does not silently no-op on a directory of mixed files)
# -----------------------------------------------------------------------------
i4_tree_wide_scope() {
  local tmp
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" RETURN
  mkdir -p "$tmp/tests" "$tmp/Release/v1.0.0/review"
  # 198.51.100.0/24 is RFC 5737 documentation range — public-shaped, never
  # routed to a real host; safe to commit as a fixture literal.
  printf 'IP=198.51.100.52\n' > "$tmp/tests/fixture.sh"
  printf 'codename: ProjectBeta\n' > "$tmp/Release/v1.0.0/review/old.md"

  local rc
  bash "$PROJECT_ROOT/Release/redact-scan.sh" "$tmp" >/dev/null 2>&1
  rc=$?
  [ "$rc" -ne 0 ]
}

# -----------------------------------------------------------------------------
# C5 — no real TYO IP in tracked tests
# -----------------------------------------------------------------------------
c5_no_real_tyo_ip_in_tests() {
  ! grep -RnE --include='*.sh' '\b103\.117\.102\.52\b' "$PROJECT_ROOT/tests/" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# C6 — no real machine codename in tracked tests
# -----------------------------------------------------------------------------
c6_no_real_machine_name_in_tests() {
  ! grep -RnE --include='*.sh' '\bTK-MBP16-M3\b' "$PROJECT_ROOT/tests/" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# C4 — no private project codenames in golden manifests
# -----------------------------------------------------------------------------
c4_no_codenames_in_golden_manifests() {
  ! grep -RnE -i '(openclaw|aristotle|maxwell|ai-rtos|macaudit|please[-_]continue|niu[-_ ]hybrid|surge[-_]vpn)' \
       "$PROJECT_ROOT/tests/golden/" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# C7 — FULL→MAX rename complete in shipping artifacts
# -----------------------------------------------------------------------------
c7_no_full_in_shipping() {
  # Allowed words: "full", "Fully" — only flag standalone token "FULL" or strings like "FULL tier"/"FULL mode"/"FULL version"
  local hits
  hits=$(grep -nE '\bFULL\b' \
    "$PROJECT_ROOT/README.md" \
    "$PROJECT_ROOT/README.zh-CN.md" \
    "$PROJECT_ROOT/Release/example-output/CLAUDE.md" \
    "$PROJECT_ROOT/Release/example-output/INDEX.md" \
    "$PROJECT_ROOT/Release/example-output/REPORT.md" \
    "$PROJECT_ROOT/Release/structural-gate.sh" \
    2>/dev/null | grep -vE '\bMIN/COMMON/MAX\b|MAX \(formerly FULL\)' || true)
  [ -z "$hits" ]
}

# -----------------------------------------------------------------------------
# C8 — example-output rule filenames match generator spec
# -----------------------------------------------------------------------------
c8_example_filenames_match_spec() {
  # Spec from TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md COMMON rule list
  local expected="01-identity 02-execution 03-quality 04-decision 05-file-safety 06-security 07-memory 08-coding 09-anti-patterns 10-plugins-skills"
  local actual=""
  if [ -d "$PROJECT_ROOT/Release/example-output/rules" ]; then
    actual=$(cd "$PROJECT_ROOT/Release/example-output/rules" && \
             ls *.md 2>/dev/null | sed 's/\.md$//' | sort | tr '\n' ' ' | sed 's/ $//')
  fi
  local expected_sorted
  expected_sorted=$(printf '%s\n' $expected | sort | tr '\n' ' ' | sed 's/ $//')
  [ "$actual" = "$expected_sorted" ]
}

# -----------------------------------------------------------------------------
# C3 — lite-prompt has no private identifiers
# -----------------------------------------------------------------------------
c3_lite_prompt_no_private_ids() {
  local f="$PROJECT_ROOT/Release/lite-prompt-MIN.md"
  [ -f "$f" ] || return 0  # absent is also acceptable (delete-and-document path)
  ! grep -E '老大|Jarvis|TK 开发宪法|🚀' "$f" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# C2 — HANDOFF.md is not tracked by git
# -----------------------------------------------------------------------------
c2_handoff_not_tracked() {
  cd "$PROJECT_ROOT" || return 1
  ! git ls-files --error-unmatch HANDOFF.md >/dev/null 2>&1
}

c2_gitx_guideline_not_tracked() {
  cd "$PROJECT_ROOT" || return 1
  ! git ls-files --error-unmatch GitX_Upgrade_Guideline.md >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# I1 — deploy.sh works with default CCG_PREFIX (CLAUDE-CONF) layout
# -----------------------------------------------------------------------------
i1_deploy_default_prefix() {
  local tmp_outputs target
  tmp_outputs=$(mktemp -d)
  target=$(mktemp -d)
  trap "rm -rf '$tmp_outputs' '$target'" RETURN
  mkdir -p "$tmp_outputs/CLAUDE-CONF-MIN-20260420/rules"
  printf '# Test fixture\n' > "$tmp_outputs/CLAUDE-CONF-MIN-20260420/CLAUDE.md"
  printf '# rule 01\n'     > "$tmp_outputs/CLAUDE-CONF-MIN-20260420/rules/01-identity.md"

  # Default CCG_PREFIX should be CLAUDE-CONF (no env var set).
  bash "$PROJECT_ROOT/Release/deploy.sh" MIN "$target" --base "$tmp_outputs" --force \
    >/dev/null 2>&1
  local rc=$?
  [ "$rc" -eq 0 ] && [ -f "$target/CLAUDE.md" ] && [ -f "$target/rules/01-identity.md" ]
}

# -----------------------------------------------------------------------------
# I2 — README.zh-CN does not present gitignored paths as authoritative
# -----------------------------------------------------------------------------
i2_zh_cn_no_authoritative_gitignored() {
  ! grep -nE '权威.*outputs|outputs.*权威|权威.*rules-legacy' \
      "$PROJECT_ROOT/README.zh-CN.md" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# I3 — number reconciliation
# -----------------------------------------------------------------------------
i3_release_readme_family_count() {
  # Should NOT say "9 families" when the actual family bullet count is 8.
  ! grep -E '\b9 families\b|9 个家族|9 个类别' "$PROJECT_ROOT/Release/README.md" >/dev/null 2>&1
}

i3_changelog_family_count() {
  ! grep -E '\b9 families\b|9 个家族' "$PROJECT_ROOT/Release/v1.0.2/CHANGELOG.md" >/dev/null 2>&1
}

i3_zh_cn_categories_24() {
  # Either uses "24" or omits the count; "20+" is wrong (actual = 24)
  ! grep -E '20\+ 类|17 类|17 categories' "$PROJECT_ROOT/README.zh-CN.md" >/dev/null 2>&1
}

i3_example_report_categories() {
  ! grep -E '\b17 redaction categories\b' \
      "$PROJECT_ROOT/Release/example-output/REPORT.md" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# I5 — test-p1-fixes.sh dead-code pipeline removed
# -----------------------------------------------------------------------------
i5_no_dead_pipe() {
  # The bug pattern is: `grep -q[F]? PATTERN FILE | grep -q…`
  # — i.e., grep already reading from a file, then piping (its empty stdout) into another grep.
  # `echo "$X" | grep -q` is a different, legitimate pipeline and must not be flagged.
  ! grep -nE "grep -q[F]? '[^']*' \"[^\"]*\" \| grep -qF?" \
      "$PROJECT_ROOT/tests/test-p1-fixes.sh" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# I6 — tests using outputs/ have skip guards
# -----------------------------------------------------------------------------
i6_skip_guard_present() {
  for f in test-llm-consistency.sh test-golden-diff.sh; do
    grep -qE 'SKIP|outputs.*missing|skip-when-missing' \
      "$PROJECT_ROOT/tests/$f" 2>/dev/null || return 1
  done
}

# -----------------------------------------------------------------------------
# I7 — find -maxdepth before -name (POSIX/GNU ordering)
# -----------------------------------------------------------------------------
i7_find_maxdepth_ordering() {
  # Bad: `find ... -name ... -maxdepth N` (GNU warns)
  ! grep -nE 'find [^|]+-name [^|]+-maxdepth' \
      "$PROJECT_ROOT/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# I8 — xargs sh -c uses positional args, not literal {} interpolation
# -----------------------------------------------------------------------------
i8_xargs_no_literal_interpolation() {
  # Bad: `xargs -I{} sh -c '... {} ...'`
  # Good: `xargs -I{} sh -c '... "$1" ...' _ {}`
  local hits
  hits=$(grep -nE "xargs -I\{\} sh -c '[^']*\{\}" \
      "$PROJECT_ROOT/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md" 2>/dev/null || true)
  [ -z "$hits" ]
}

# -----------------------------------------------------------------------------
# Run scenarios
# -----------------------------------------------------------------------------
echo "================================================================"
echo "  Audit BDD scenarios — v1.0.2 post-review fixes"
echo "================================================================"
echo

scenario "C1 redact-scan catches leak inside review/"             c1_review_subdir_leak_caught
scenario "I4 redact-scan tree-wide scope catches mixed leaks"     i4_tree_wide_scope
scenario "C5 no real TYO IP in tests/"                            c5_no_real_tyo_ip_in_tests
scenario "C6 no real machine name in tests/"                      c6_no_real_machine_name_in_tests
scenario "C4 no private codenames in tests/golden/"               c4_no_codenames_in_golden_manifests
scenario "C7 FULL→MAX rename complete in shipping artifacts"      c7_no_full_in_shipping
scenario "C8 example-output filenames match generator spec"       c8_example_filenames_match_spec
scenario "C3 lite-prompt-MIN has no private identifiers"          c3_lite_prompt_no_private_ids
scenario "C2 HANDOFF.md is not tracked by git"                    c2_handoff_not_tracked
scenario "C2 GitX_Upgrade_Guideline.md is not tracked by git"     c2_gitx_guideline_not_tracked
scenario "I1 deploy.sh works with default CCG_PREFIX=CLAUDE-CONF" i1_deploy_default_prefix
scenario "I2 README.zh-CN doesn't cite gitignored as authoritative" i2_zh_cn_no_authoritative_gitignored
scenario "I3 Release/README.md doesn't claim 9 families"          i3_release_readme_family_count
scenario "I3 CHANGELOG doesn't claim 9 families"                  i3_changelog_family_count
scenario "I3 README.zh-CN doesn't claim 20+/17 categories"        i3_zh_cn_categories_24
scenario "I3 example REPORT.md doesn't claim 17 categories"       i3_example_report_categories
scenario "I5 test-p1-fixes.sh has no dead grep pipe"              i5_no_dead_pipe
scenario "I6 tests using outputs/ have skip guards"               i6_skip_guard_present
scenario "I7 find -maxdepth before -name in generator prompt"     i7_find_maxdepth_ordering
scenario "I8 xargs sh -c uses positional args, not literal {}"    i8_xargs_no_literal_interpolation

echo
echo "================================================================"
echo "  Result: ${PASS} pass / ${FAIL} fail"
echo "================================================================"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed:"
  for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi
exit 0
