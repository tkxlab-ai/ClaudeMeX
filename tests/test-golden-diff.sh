#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Golden-diff test: outputs/ vs tests/golden/ SHA-256 manifests
#
# Usage:
#   bash tests/test-golden-diff.sh          # compare (exit 0 = match, 1 = diverge)
#   bash tests/test-golden-diff.sh --update # regenerate golden manifests from outputs
#
# BSD/macOS compatible (uses shasum -a 256, not sha256sum).
#
# RUN_ALL: optional (per-machine drift detection — opt-in via RUN_ALL_OPTIONAL=1)
# This test compares the user's locally generated outputs/ against snapshots
# under tests/golden/. Hash drift here is expected user content evolution, not
# a regression of the generator. Skipped from the default tests/run_all.sh run.
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUTS_DIR="$PROJECT_ROOT/outputs"
GOLDEN_DIR="$SCRIPT_DIR/golden"
MODE="check"

TIERS="MIN COMMON MAX"

# ── Arg parsing ──
for arg in "$@"; do
  case "$arg" in
    --update) MODE="update" ;;
    --help|-h)
      echo "Usage: $0 [--update]"
      echo "  --update  Regenerate golden manifests from current outputs/"
      exit 0
      ;;
  esac
done

# ── Pre-flight ──
# outputs/ is gitignored (per-machine generator output). When absent,
# this test cannot run — SKIP rather than fail so a fresh clone passes CI.
if [ ! -d "$OUTPUTS_DIR" ]; then
  echo "SKIP: outputs/ missing at $OUTPUTS_DIR (gitignored — run the generator first)"
  exit 0
fi

# ── Helpers ──
green() { printf "\033[32mPASS\033[0m %s\n" "$1"; }
red()   { printf "\033[31mFAIL\033[0m %s\n" "$1"; }
yellow(){ printf "\033[33mINFO\033[0m %s\n" "$1"; }

# Find the latest dated directory for a given tier pattern.
# e.g. find_latest_tier "TKCC-CONF-MIN" → "TKCC-CONF-MIN-20260420"
find_latest_tier() {
  local prefix="$1"
  local best=""
  local d
  for d in "$OUTPUTS_DIR"/${prefix}-*/; do
    [ -d "$d" ] || continue
    local base
    base="$(basename "$d")"
    if [ -z "$best" ] || [[ "$base" > "$best" ]]; then
      best="$base"
    fi
  done
  echo "$best"
}

# Compute sha256 + line count for a single file.
# Output: "<sha256>  <lines>  <relative_path>"
file_signature() {
  local fpath="$1"
  local relpath="$2"
  local sha lines
  sha=$(shasum -a 256 "$fpath" | awk '{print $1}')
  lines=$(wc -l < "$fpath" | tr -d ' ')
  echo "${sha}  ${lines}  ${relpath}"
}

# Scan a tier directory, emit signatures (sorted by relpath).
# Skips dotfiles (.DS_Store etc).
scan_tier() {
  local tier_dir="$1"
  local rel_base="$2"
  local f
  # Use find to get all regular files, skip dotfiles
  while IFS= read -r f; do
    local relpath="${f#${tier_dir}}"
    # strip leading /
    relpath="${relpath#/}"
    file_signature "$f" "$rel_base/$relpath"
  done < <(find "$tier_dir" -type f ! -name '.*' | LC_ALL=C sort)
}

# ── UPDATE mode: regenerate golden manifests ──
if [ "$MODE" = "update" ]; then
  echo "=== Golden-diff: Regenerating golden manifests ==="
  echo

  rm -rf "$GOLDEN_DIR"
  mkdir -p "$GOLDEN_DIR"

  GENERATED=0
  FAILED=0

  for tier in $TIERS; do
    local_dir="$(find_latest_tier "TKCC-CONF-${tier}")"
    if [ -z "$local_dir" ] || [ ! -d "$OUTPUTS_DIR/$local_dir" ]; then
      red "Tier $tier: no outputs/ directory found — skipped"
      FAILED=$((FAILED + 1))
      continue
    fi

    tier_golden="$GOLDEN_DIR/$tier"
    mkdir -p "$tier_golden"
    manifest="$tier_golden/manifest.txt"

    echo "# Golden manifest for $tier" > "$manifest"
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')" >> "$manifest"
    echo "# Source:  outputs/$local_dir/" >> "$manifest"
    echo "# Format:  <sha256>  <lines>  <relative_path>" >> "$manifest"
    echo "" >> "$manifest"

    scan_tier "$OUTPUTS_DIR/$local_dir" "$local_dir" >> "$manifest"

    file_count=$(grep -cv '^#\|^$' "$manifest" || true)
    green "Tier $tier: $file_count files → $tier_golden/manifest.txt"
    GENERATED=$((GENERATED + file_count))
  done

  echo
  echo "=== Done: $GENERATED file signatures written to tests/golden/ ==="
  if [ "$FAILED" -gt 0 ]; then
    echo "Warnings: $FAILED tier(s) skipped (no source directory)"
  fi
  exit 0
fi

# ── CHECK mode: compare outputs vs golden ──
TESTS_PASSED=0
TESTS_FAILED=0
DIVERGED_FILES=""
MISSING_GOLDEN=""
MISSING_OUTPUTS=""

echo "=== Golden-diff: Comparing outputs/ vs tests/golden/ ==="
echo

OVERALL_OK=true

for tier in $TIERS; do
  echo "--- Tier: $tier ---"

  tier_golden="$GOLDEN_DIR/$tier"
  local_dir="$(find_latest_tier "TKCC-CONF-${tier}")"

  # Check golden manifest exists
  if [ ! -f "$tier_golden/manifest.txt" ]; then
    red "Golden manifest missing: $tier_golden/manifest.txt"
    echo "  → Run '$0 --update' to generate golden baselines"
    MISSING_GOLDEN="${MISSING_GOLDEN}${MISSING_GOLDEN:+, }$tier"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    OVERALL_OK=false
    echo
    continue
  fi

  # Check outputs directory exists
  if [ -z "$local_dir" ] || [ ! -d "$OUTPUTS_DIR/$local_dir" ]; then
    red "Outputs directory missing for tier $tier"
    MISSING_OUTPUTS="${MISSING_OUTPUTS}${MISSING_OUTPUTS:+, }$tier"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    OVERALL_OK=false
    echo
    continue
  fi

  # Load golden signatures into associative-like temp file
  golden_tmp=$(mktemp)
  grep -v '^#\|^$' "$tier_golden/manifest.txt" > "$golden_tmp" || true

  # Generate current signatures
  current_tmp=$(mktemp)
  scan_tier "$OUTPUTS_DIR/$local_dir" "$local_dir" > "$current_tmp"

  tier_diverged=0
  tier_ok=0

  # Check each golden file against current
  while IFS= read -r gline; do
    g_sha=$(echo "$gline" | awk '{print $1}')
    g_lines=$(echo "$gline" | awk '{print $2}')
    g_path=$(echo "$gline" | awk '{$1=""; $2=""; print}' | sed 's/^  *//')
    g_basename=$(basename "$g_path")

    # Find current file
    cur_file="$OUTPUTS_DIR/$local_dir/$g_basename"
    # Handle files in subdirectories (rules/)
    if [ ! -f "$cur_file" ]; then
      # Try path as relative from source dir
      rel_from_source="${g_path#TKCC-CONF-${tier}-*/}"
      if [ -f "$OUTPUTS_DIR/$local_dir/$rel_from_source" ]; then
        cur_file="$OUTPUTS_DIR/$local_dir/$rel_from_source"
      fi
    fi

    if [ ! -f "$cur_file" ]; then
      red "[MISSING] $g_path (exists in golden, not in outputs/)"
      DIVERGED_FILES="${DIVERGED_FILES}${DIVERGED_FILES:+; }$g_path (DELETED)"
      tier_diverged=$((tier_diverged + 1))
      continue
    fi

    cur_sha=$(shasum -a 256 "$cur_file" | awk '{print $1}')
    cur_lines=$(wc -l < "$cur_file" | tr -d ' ')

    if [ "$g_sha" = "$cur_sha" ] && [ "$g_lines" = "$cur_lines" ]; then
      tier_ok=$((tier_ok + 1))
    else
      red "[DIVERGED] $g_basename"
      if [ "$g_sha" != "$cur_sha" ]; then
        echo "         sha256 changed: ${g_sha:0:16}... → ${cur_sha:0:16}..."
      fi
      if [ "$g_lines" != "$cur_lines" ]; then
        echo "         lines changed: $g_lines → $cur_lines"
      fi
      DIVERGED_FILES="${DIVERGED_FILES}${DIVERGED_FILES:+; }$g_path"
      tier_diverged=$((tier_diverged + 1))
    fi
  done < "$golden_tmp"

  # Check for NEW files in outputs/ not in golden
  while IFS= read -r cline; do
    c_path=$(echo "$cline" | awk '{$1=""; $2=""; print}' | sed 's/^  *//')
    c_basename=$(basename "$c_path")

    # Check if this file exists in golden
    found=0
    while IFS= read -r gline_check; do
      g_path_check=$(echo "$gline_check" | awk '{$1=""; $2=""; print}' | sed 's/^  *//')
      if [ "$(basename "$g_path_check")" = "$c_basename" ]; then
        found=1
        break
      fi
    done < "$golden_tmp"

    if [ "$found" -eq 0 ]; then
      # Per-machine project rules (rules/11-*.md and beyond) are intentionally
      # excluded from the public golden because their filenames encode user-specific
      # project codenames. Treat them as warnings, not regressions.
      if echo "$c_path" | grep -qE 'rules/(1[1-9]|[2-9][0-9])-[^/]+\.md$'; then
        yellow "[NEW] $c_path (per-machine project rule — not in public golden, OK)"
      else
        yellow "[NEW] $c_path (in outputs/ but not in golden)"
        DIVERGED_FILES="${DIVERGED_FILES}${DIVERGED_FILES:+; }$c_path (NEW)"
        tier_diverged=$((tier_diverged + 1))
      fi
    fi
  done < "$current_tmp"

  rm -f "$golden_tmp" "$current_tmp"

  if [ "$tier_diverged" -eq 0 ]; then
    green "All $tier_ok files match golden baseline"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    red "$tier_diverged file(s) diverged ($tier_ok match)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    OVERALL_OK=false
  fi
  echo
done

# ── Summary ──
echo "==============================="
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "==============================="

if [ -n "$DIVERGED_FILES" ]; then
  echo
  echo "Diverged files:"
  echo "$DIVERGED_FILES" | tr ';' '\n' | sed 's/^/  - /'
  echo
  echo "To update golden baselines: $0 --update"
fi

if [ -n "$MISSING_GOLDEN" ]; then
  echo
  echo "Missing golden manifests for: $MISSING_GOLDEN"
fi

if [ "$OVERALL_OK" = true ]; then
  exit 0
else
  exit 1
fi
