#!/usr/bin/env bash
# tests/run_all.sh — Single entry point for the ClaudeMeX test suite.
#
# Runs every tests/test-*.sh in alphabetic order, plus the audit BDD suite.
# Exit 0 if every executed test exits 0 (skips count as pass); exit 1 on any
# failure.
#
# Tests that depend on per-machine artifacts (outputs/) are expected to skip
# gracefully when those artifacts are absent — see tests/test-llm-consistency.sh
# and tests/test-golden-diff.sh for the skip-guard pattern.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
SKIP=0
FAIL_NAMES=()

red()   { printf '\033[0;31m%s\033[0m' "$*"; }
green() { printf '\033[0;32m%s\033[0m' "$*"; }
blue()  { printf '\033[0;34m%s\033[0m' "$*"; }
gray()  { printf '\033[0;90m%s\033[0m' "$*"; }

echo "================================================================"
echo "  ClaudeMeX — full test suite (tests/run_all.sh)"
echo "================================================================"
echo ""

# Order: deterministic, alphabetic; the audit BDD goes last because it
# exercises the cross-cutting invariants set up by the earlier suites.
suites=()
while IFS= read -r f; do
  case "$(basename "$f")" in
    test-*.sh) suites+=("$f") ;;
  esac
done < <(find "$SCRIPT_DIR" -maxdepth 1 -type f -name 'test-*.sh' | sort)

if [ "${#suites[@]}" -eq 0 ]; then
  echo "$(red ERROR): no tests/test-*.sh files found under $SCRIPT_DIR" >&2
  exit 1
fi

RUN_ALL_OPTIONAL="${RUN_ALL_OPTIONAL:-0}"

for suite in "${suites[@]}"; do
  name="$(basename "$suite")"
  printf '  %s ' "$(blue "▸")"
  printf '%-44s ' "$name"

  # Honour `RUN_ALL: optional` opt-out for per-machine / drift-detection tests.
  if [ "$RUN_ALL_OPTIONAL" != "1" ] && grep -q '^# RUN_ALL: optional' "$suite"; then
    printf '%s (opt-in: RUN_ALL_OPTIONAL=1)\n' "$(gray SKIP)"
    SKIP=$((SKIP + 1))
    continue
  fi

  out=$(bash "$suite" 2>&1)
  rc=$?

  if [ "$rc" -eq 0 ]; then
    if echo "$out" | grep -qE '^SKIP:|^\[SKIP\]'; then
      printf '%s\n' "$(gray SKIP)"
      SKIP=$((SKIP + 1))
    else
      printf '%s\n' "$(green PASS)"
      PASS=$((PASS + 1))
    fi
  else
    printf '%s (exit %d)\n' "$(red FAIL)" "$rc"
    FAIL=$((FAIL + 1))
    FAIL_NAMES+=("$name")
    # Surface the last few lines for triage.
    echo "$out" | tail -5 | sed 's/^/      /'
  fi
done

echo ""
echo "================================================================"
echo "  Result: $(green "${PASS} pass") / $(red "${FAIL} fail") / $(gray "${SKIP} skip")"
echo "================================================================"

if [ "$FAIL" -gt 0 ]; then
  echo "Failed suites:"
  for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi
exit 0
