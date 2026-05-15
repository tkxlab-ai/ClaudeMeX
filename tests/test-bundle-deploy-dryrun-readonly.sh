#!/usr/bin/env bash
# Regression test: bundle-internal deploy.sh `--dry-run` MUST be both
# state-isolated AND functionally correct (i.e. actually iterate rules).
#
# History:
#   - 2026-05-09 Codex stop-hook caught that the bundle-internal deploy.sh
#     truncated INSTALL.log unconditionally + appended via bare `>>`,
#     making --uninstall delete files that were never installed.
#   - 2026-05-09 Codex stop-hook later caught that the first-pass test
#     could PASS when --dry-run was broken (e.g. flag silently ignored,
#     install() early-exits, or stub merely prints "DRY-RUN" without doing
#     anything). The fix below upgrades exit-code and marker checks from
#     informational to gating, and adds a positive-coverage assertion that
#     every rule fixture file name actually appears in --dry-run output —
#     so a no-op stub that "looks compliant" cannot pass.
#
# Safety design:
#   - Each candidate deploy.sh + rules/ is COPIED into a per-bundle sandbox
#     under $TMPROOT. The script under test runs in the sandbox; live
#     PROJECT_ROOT/outputs/ is never written to or rm'd from.
#   - HOME redirected to a sandbox subtree so accidental real installs
#     cannot escape.
#   - `trap` removes the entire sandbox on EXIT/INT/TERM.
#
# Detection design — five gating assertions, all must pass:
#   A — exit 0 (script ran cleanly, didn't crash on `--dry-run`).
#   B — DRY-RUN marker present in stdout (flag was recognised + a dry-run
#       branch was taken; absence implies silent ignore).
#   C — bundle dir's INSTALL.log absent (no LOG mutation).
#   D — sandbox HOME's target dir empty (no real cp).
#   E — every rule fixture file name appears in stdout at least once
#       (positive coverage: dry-run actually iterated rules; a stub that
#       just prints "DRY-RUN summary" and exits cannot satisfy this).
#
# Self-test (harness trustworthiness):
#   Five planted-bug stubs cover the failure modes:
#     - leak           — original bug (writes LOG, never writes target under dry-run)
#     - silent         — flag silently ignored (no DRY-RUN marker; goes install path)
#     - noop           — flag parsed but body skipped (no rules iterated)
#     - banner         — prints rule names but no per-rule action verb (false
#                        positive for naive coverage check); E catches via verb
#                        list.
#     - dryrun-banner  — per-rule line with `DRY-RUN: <fname>` only — mode marker
#                        without an action verb. E must NOT count DRY-RUN itself
#                        as action evidence; a real action verb (cp/install/NEW)
#                        is required.
#   The harness must catch each via at least one of A/B/C/D/E. If any
#   planted bug slips through, exit 2 with a FATAL marker.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPROOT="$(mktemp -d -t bundle-deploy-test.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT INT TERM

PASS=0
FAIL=0

green() { printf '\033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
red()   { printf '\033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
gray()  { printf '\033[90m%s\033[0m %s\n' "$1" "$2"; }

# Run one deploy.sh through the gauntlet inside an isolated sandbox.
# Globals set:
#   ASSERT_A / ASSERT_B / ASSERT_C / ASSERT_D / ASSERT_E
#     0 = check passed (no anomaly), 1 = check observed an anomaly
#
# Args:
#   $1 — label
#   $2 — abs path to candidate deploy.sh
#   $3 — abs path to a directory containing rules/*.md (may be empty/missing)
#   $4 — expected outcome: "clean" (all 5 must pass) or "buggy" (≥1 must fail)
check_one() {
  local label="$1" deploy_src="$2" rules_src="$3" expect="$4"

  ASSERT_A=0 ASSERT_B=0 ASSERT_C=0 ASSERT_D=0 ASSERT_E=0

  local sandbox safe_label
  safe_label="$(printf '%s' "$label" | tr -c '[:alnum:]._-' '_')"
  sandbox="$TMPROOT/$safe_label"
  mkdir -p "$sandbox/bundle/rules" "$sandbox/home"
  cp "$deploy_src" "$sandbox/bundle/deploy.sh"
  chmod +x "$sandbox/bundle/deploy.sh"

  # Seed up to 3 distinguishable rule fixtures; record names for E.
  local fixture_names=()
  if [ -d "$rules_src" ]; then
    local n=0
    for f in "$rules_src"/*.md; do
      [ -f "$f" ] || continue
      cp "$f" "$sandbox/bundle/rules/"
      fixture_names+=("$(basename "$f")")
      n=$((n+1))
      [ "$n" -ge 3 ] && break
    done
  fi
  if [ "${#fixture_names[@]}" -eq 0 ]; then
    printf 'stub-a\n' > "$sandbox/bundle/rules/00-fixture-a.md"
    printf 'stub-b\n' > "$sandbox/bundle/rules/01-fixture-b.md"
    fixture_names=("00-fixture-a.md" "01-fixture-b.md")
  fi

  local stdout_log="$sandbox/dryrun.out"
  local exit_code=0
  HOME="$sandbox/home" \
    bash "$sandbox/bundle/deploy.sh" --dry-run > "$stdout_log" 2>&1 \
    || exit_code=$?

  # ── A: clean exit ──
  local label_A="$label/A: --dry-run exits 0"
  if [ "$exit_code" -eq 0 ]; then
    if [ "$expect" = "clean" ]; then
      green "$label_A"
    else
      gray "skip" "$label_A (planted bug exited cleanly — A did not detect; other gates may)"
    fi
  else
    ASSERT_A=1
    if [ "$expect" = "buggy" ]; then
      green "$label_A (planted bug exited $exit_code — A detected)"
    else
      red "$label_A (exit=$exit_code; tail: $(tail -2 "$stdout_log" | tr '\n' '|'))"
    fi
  fi

  # ── B: DRY-RUN marker observed (proves flag was recognised) ──
  local label_B="$label/B: --dry-run marker present in stdout"
  if grep -qiE 'DRY[._-]?RUN' "$stdout_log"; then
    [ "$expect" = "clean" ] && green "$label_B" || gray "skip" "$label_B (planted bug printed marker — B did not detect; other gates may)"
  else
    ASSERT_B=1
    if [ "$expect" = "buggy" ]; then
      green "$label_B (planted bug omitted marker — B detected)"
    else
      red "$label_B (no DRY-RUN marker — flag may be silently ignored)"
    fi
  fi

  # ── C: bundle's INSTALL.log absent (no LOG mutation) ──
  local label_C="$label/C: --dry-run does not mutate bundle INSTALL.log"
  if [ -e "$sandbox/bundle/INSTALL.log" ]; then
    ASSERT_C=1
    if [ "$expect" = "buggy" ]; then
      green "$label_C (planted bug wrote INSTALL.log — C detected)"
    else
      red "$label_C (INSTALL.log appeared after --dry-run)"
    fi
  else
    [ "$expect" = "clean" ] && green "$label_C" || gray "skip" "$label_C (planted bug did not leak LOG — C did not detect; other gates may)"
  fi

  # ── D: target dir empty (no real cp) ──
  local label_D="$label/D: --dry-run does not write to HOME/.claude/rules"
  if [ -d "$sandbox/home/.claude/rules" ] && \
     [ -n "$(ls -A "$sandbox/home/.claude/rules" 2>/dev/null)" ]; then
    ASSERT_D=1
    if [ "$expect" = "buggy" ]; then
      green "$label_D (planted bug wrote target — D detected)"
    else
      red "$label_D (files appeared in target dir)"
    fi
  else
    [ "$expect" = "clean" ] && green "$label_D" || gray "skip" "$label_D (planted bug did not write target — D did not detect; other gates may)"
  fi

  # ── E: per-rule action coverage ──
  # Each fixture name must appear on a line that ALSO contains an action
  # VERB (cp | copy | install | would | NEW | SKIP | FORCE). The DRY-RUN
  # marker itself is intentionally NOT in this list — it is a mode label,
  # not evidence of an action. A stub that prints
  #     "  DRY-RUN: 00-fixture-a.md"
  # for each rule (per-rule banner with mode-marker only) must fail E.
  # Real deploy.sh output naturally has both: lines like
  #     "  DRY-RUN: cp <src> <dst>"   (matches: cp)
  #     "[time]   NEW:    <fname>"    (matches: NEW)
  # so removing DRY-RUN from the verb set does not affect legitimate output.
  local label_E="$label/E: every rule has per-line action verb"
  local action_re='\bcp\b|\bcopy\b|\binstall(ed|ing|s)?\b|\bwould\b|\bNEW\b|\bSKIP\b|\bFORCE\b'
  local missing=()
  local fname
  for fname in "${fixture_names[@]}"; do
    # Find any line containing the fixture name AND action evidence.
    if ! grep -F -- "$fname" "$stdout_log" 2>/dev/null \
         | grep -qiE "$action_re"; then
      missing+=("$fname")
    fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    [ "$expect" = "clean" ] && green "$label_E" || gray "skip" "$label_E (planted bug produced action lines for all rules — E did not detect; other gates may)"
  else
    ASSERT_E=1
    if [ "$expect" = "buggy" ]; then
      green "$label_E (planted bug failed action coverage for ${#missing[@]} rule(s): ${missing[*]} — E detected)"
    else
      red "$label_E (no action-context line for: ${missing[*]})"
    fi
  fi
}

# ── Discover candidate bundles ──

mapfile -t BUNDLE_DEPLOYS < <(
  find "$PROJECT_ROOT/outputs" -maxdepth 2 -type f -name 'deploy.sh' \
       \! -path '*/.deprecated*/*' 2>/dev/null | sort
)

if [ "${#BUNDLE_DEPLOYS[@]}" -eq 0 ]; then
  echo "no bundle-internal deploy.sh found under outputs/ — nothing to test"
  echo "============================================"
  echo "  PASS: 0  FAIL: 0  (no candidates)"
  echo "============================================"
  exit 0
fi

echo "Discovered ${#BUNDLE_DEPLOYS[@]} bundle-internal deploy.sh candidate(s)"
echo ""

for d in "${BUNDLE_DEPLOYS[@]}"; do
  bundle_dir="$(dirname "$d")"
  bundle_name="$(basename "$bundle_dir")"
  rules_src="$bundle_dir/rules"
  check_one "$bundle_name" "$d" "$rules_src" "clean"
done

# ── Self-test: three planted bugs, each must be caught by ≥1 gate ──

echo ""
echo "----- self-test: planted-bug detection -----"
echo ""

selftest_dir="$TMPROOT/_selftest_src"
mkdir -p "$selftest_dir/rules"
echo "stub-a" > "$selftest_dir/rules/00-fixture-a.md"
echo "stub-b" > "$selftest_dir/rules/01-fixture-b.md"

# Stub 1 — "leak": dry-run skips cp but still writes LOG (the original bug)
cat > "$selftest_dir/leak-deploy.sh" <<'LEAK'
#!/usr/bin/env bash
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${HOME}/.claude/rules"
LOG_FILE="${SRC_DIR}/INSTALL.log"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
mkdir -p "$DEST_DIR"
: > "$LOG_FILE"
for rule in "$SRC_DIR"/rules/*.md; do
  [ -f "$rule" ] || continue
  fname="$(basename "$rule")"
  target="$DEST_DIR/$fname"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  DRY-RUN: cp $rule $target"
  else
    cp "$rule" "$target"
  fi
  echo "$target" >> "$LOG_FILE"
done
echo "DRY-RUN summary"
LEAK
chmod +x "$selftest_dir/leak-deploy.sh"

# Stub 2 — "silent": --dry-run flag silently ignored, runs install path
cat > "$selftest_dir/silent-deploy.sh" <<'SILENT'
#!/usr/bin/env bash
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${HOME}/.claude/rules"
LOG_FILE="${SRC_DIR}/INSTALL.log"
# No --dry-run parsing at all; treats it as nothing
mkdir -p "$DEST_DIR"
: > "$LOG_FILE"
for rule in "$SRC_DIR"/rules/*.md; do
  [ -f "$rule" ] || continue
  fname="$(basename "$rule")"
  target="$DEST_DIR/$fname"
  cp "$rule" "$target"
  echo "$target" >> "$LOG_FILE"
done
SILENT
chmod +x "$selftest_dir/silent-deploy.sh"

# Stub 3 — "noop": parses flag but never iterates rules; pretends to be dry-run
cat > "$selftest_dir/noop-deploy.sh" <<'NOOP'
#!/usr/bin/env bash
set -euo pipefail
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN: ok"
  exit 0
fi
# real install would go here
NOOP
chmod +x "$selftest_dir/noop-deploy.sh"

# Stub 4 — "banner": prints DRY-RUN marker AND every rule name, but no
# per-rule action verb. Mimics a stub that lists fixtures (e.g. via
# `ls rules/`) without actually simulating cp/install. E must catch this.
cat > "$selftest_dir/banner-deploy.sh" <<'BANNER'
#!/usr/bin/env bash
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN mode active"
  echo "Available rules:"
  for rule in "$SRC_DIR"/rules/*.md; do
    [ -f "$rule" ] || continue
    echo "  - $(basename "$rule")"   # mention only, no action verb
  done
  echo "Bye"
  exit 0
fi
BANNER
chmod +x "$selftest_dir/banner-deploy.sh"

# Stub 5 — "dryrun-banner": per-rule banner with DRY-RUN: prefix on every
# rule line, but no real action verb (cp/install/etc). The DRY-RUN marker
# alone is a mode label, not action evidence. E must reject this.
cat > "$selftest_dir/dryrun-banner-deploy.sh" <<'DRYRUNBANNER'
#!/usr/bin/env bash
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
if [ "$DRY_RUN" -eq 1 ]; then
  for rule in "$SRC_DIR"/rules/*.md; do
    [ -f "$rule" ] || continue
    echo "  DRY-RUN: $(basename "$rule")"   # mode marker without action verb
  done
  echo "DRY-RUN done"
  exit 0
fi
DRYRUNBANNER
chmod +x "$selftest_dir/dryrun-banner-deploy.sh"

# Run each planted-bug stub; record whether ≥1 gate detected the bug.
HARNESS_OK=1

for stub in leak silent noop banner dryrun-banner; do
  check_one "self-test:$stub" \
            "$selftest_dir/${stub}-deploy.sh" \
            "$selftest_dir/rules" \
            "buggy"
  detected=$((ASSERT_A + ASSERT_B + ASSERT_C + ASSERT_D + ASSERT_E))
  if [ "$detected" -ge 1 ]; then
    green "self-test:$stub: harness caught planted bug (A=$ASSERT_A B=$ASSERT_B C=$ASSERT_C D=$ASSERT_D E=$ASSERT_E)"
  else
    red "self-test:$stub: harness MISSED planted bug — gate is not trustworthy"
    HARNESS_OK=0
  fi
  echo ""
done

if [ "$HARNESS_OK" -eq 0 ]; then
  printf '\033[31mFATAL\033[0m harness self-test failed to detect ≥1 planted bug — gate cannot be trusted, exiting non-zero\n'
  echo "============================================"
  echo "  PASS: $PASS  FAIL: $FAIL  HARNESS: BROKEN"
  echo "============================================"
  exit 2
fi

echo "============================================"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "============================================"
[ "$FAIL" -eq 0 ] || exit 1
