#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# TDD test for LLM behavior consistency — structural validation of outputs/
# Verifies: CLAUDE.md sections, rules metadata, cross-tier mapping, INDEX dead refs
# Usage: bash tests/test-llm-consistency.sh
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUTS="$PROJECT_ROOT/outputs"
DATA="$SCRIPT_DIR/data/required-sections.txt"

# outputs/ is gitignored (per-machine generator output). When absent,
# this test cannot run against real artifacts — SKIP so fresh clones pass CI.
if [ ! -d "$OUTPUTS" ]; then
  echo "SKIP: outputs/ missing at $OUTPUTS (gitignored — run the generator first)"
  exit 0
fi

PASS=0; FAIL=0; TESTS=0
pass() { PASS=$((PASS + 1)); TESTS=$((TESTS + 1)); echo "✅ PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TESTS=$((TESTS + 1)); echo "❌ FAIL: $1"; }

# ── Helpers ──
latest_tier() {
  local prefix="$1"
  ls -d "${OUTPUTS}/${prefix}-"* 2>/dev/null | sort | tail -1
}

MIN_DIR="$(latest_tier TKCC-CONF-MIN)"
COM_DIR="$(latest_tier TKCC-CONF-COMMON)"
MAX_DIR="$(latest_tier TKCC-CONF-MAX)"

check_dir() { [ -d "$1" ]; }

# =============================================================================
echo "=== T0: Prerequisites ==="
# =============================================================================
check_dir "$MIN_DIR"  && pass "MIN tier directory exists"  || fail "MIN tier directory missing"
check_dir "$COM_DIR"  && pass "COMMON tier directory exists" || fail "COMMON tier directory missing"
check_dir "$MAX_DIR"  && pass "MAX tier directory exists"    || fail "MAX tier directory missing"

[ -f "$DATA" ]        && pass "Data file exists"             || fail "Data file missing ($DATA)"

if [ ! -d "$MIN_DIR" ] || [ ! -d "$COM_DIR" ] || [ ! -d "$MAX_DIR" ]; then
  echo "FATAL: tier dirs missing"; exit 1
fi

# =============================================================================
echo ""
echo "=== T1: CLAUDE.md Required Sections ==="
# =============================================================================
check_section() {
  local tier="$1" desc="$2" pattern="$3" claude_file="$4"
  if grep -q "$pattern" "$claude_file" 2>/dev/null; then
    pass "${tier} CLAUDE.md: $desc"
  else
    fail "${tier} CLAUDE.md missing: $desc ($pattern)"
  fi
}

# Parse data file and run checks per tier
while IFS='|' read -r tier desc pattern; do
  case "$tier" in
    MIN)    [ -z "$pattern" ] && continue; check_section "MIN" "$desc" "$pattern" "$MIN_DIR/CLAUDE.md" ;;
    COMMON) [ -z "$pattern" ] && continue; check_section "COMMON" "$desc" "$pattern" "$COM_DIR/CLAUDE.md" ;;
    MAX)    [ -z "$pattern" ] && continue; check_section "MAX" "$desc" "$pattern" "$MAX_DIR/CLAUDE.md" ;;
  esac
done < "$DATA"

# =============================================================================
echo ""
echo "=== T2: Rules Metadata Completeness ==="
# =============================================================================
check_rule_meta() {
  local tier="$1" rfile="$2"
  # Must have a heading line starting with #
  if grep -q '^#' "$rfile" 2>/dev/null; then
    # Must contain at least one content keyword: 定位, 对应, 对应, purpose, 规则
    if grep -qiE '定位|对应|purpose|rule|规则|主题|身份|执行|安全|编码|反模式|记忆|plugin' "$rfile" 2>/dev/null; then
      pass "${tier} $(basename "$rfile"): has title + metadata"
    else
      fail "${tier} $(basename "$rfile"): missing metadata/定位"
    fi
  else
    fail "${tier} $(basename "$rfile"): no heading found"
  fi
}

for f in "$MIN_DIR"/rules/*.md; do
  [ -f "$f" ] && check_rule_meta "MIN" "$f"
done
for f in "$COM_DIR"/rules/*.md; do
  [ -f "$f" ] && check_rule_meta "COMMON" "$f"
done
for f in "$MAX_DIR"/rules/*.md; do
  [ -f "$f" ] && check_rule_meta "MAX" "$f"
done

# =============================================================================
echo ""
echo "=== T3: Cross-Tier Consistency (MIN ⊂ COMMON) ==="
# =============================================================================
# Each MIN rule name must map to at least one COMMON rule file or topic
while IFS='|' read -r mode min_kw com_kw; do
  [ "$mode" != "XMAP" ] && continue
  [ -z "$min_kw" ] && continue
  min_match=0
  # Check if COMMON rules dir has a file matching com_kw or min_kw
  for cf in "$COM_DIR"/rules/*.md; do
    bn="$(basename "$cf")"
    if echo "$bn" | grep -q "$com_kw" 2>/dev/null || echo "$bn" | grep -q "$min_kw" 2>/dev/null; then
      min_match=1
      break
    fi
  done
  if [ "$min_match" -eq 1 ]; then
    pass "Cross-tier: MIN '$min_kw' → COMMON '$com_kw' found"
  else
    fail "Cross-tier: MIN '$min_kw' has no COMMON match for '$com_kw'"
  fi
done < "$DATA"

# =============================================================================
echo ""
echo "=== T4: INDEX / Dead Reference Validation ==="
# =============================================================================
for tier_name in MIN COMMON MAX; do
  tdir=""
  case "$tier_name" in
    MIN)    tdir="$MIN_DIR" ;;
    COMMON) tdir="$COM_DIR" ;;
    MAX)    tdir="$MAX_DIR" ;;
  esac
  claude="$tdir/CLAUDE.md"
  rulesd="$tdir/rules"
  [ ! -f "$claude" ] && { fail "$tier_name CLAUDE.md not found"; continue; }
  [ ! -d "$rulesd" ] && { fail "$tier_name rules/ not found"; continue; }

  # Check INDEX.md exists and lists files that actually exist
  if [ -f "$tdir/INDEX.md" ]; then
    pass "${tier_name} INDEX.md exists"
    # Extract rule filenames ONLY from the 产物清单 table (rows matching | \`rules/XX-xxx.md\`)
    indexed_rules=$(grep -oE 'rules/[0-9]{2}-[a-z-]+\.md' "$tdir/INDEX.md" 2>/dev/null | sed 's|rules/||' || true)
    if [ -n "$indexed_rules" ]; then
      for ir in $indexed_rules; do
        if [ -f "$rulesd/$ir" ]; then
          pass "${tier_name} INDEX→rules: $ir exists"
        else
          fail "${tier_name} INDEX dead ref: $ir not in rules/"
        fi
      done
    fi
  else
    fail "${tier_name} INDEX.md not found"
  fi

  # Check CLAUDE.md rule index table references (e.g., `identity.md`)
  claude_rules=$(grep -oE '`[0-9]{2}-[a-z-]+\.md`' "$claude" 2>/dev/null | tr -d '`' || true)
  for cr in $claude_rules; do
    if [ -f "$rulesd/$cr" ]; then
      pass "${tier_name} CLAUDE.md→rules: $cr exists"
    else
      # Also try without leading 0 (01-identity → 01-identity) — some CLAUDE.md use short names
      short=$(echo "$cr" | sed 's/^[0-9]\{2\}-//')
      if ls "$rulesd"/*"$short" >/dev/null 2>&1; then
        pass "${tier_name} CLAUDE.md→rules: $cr (matched by keyword)"
      else
        fail "${tier_name} CLAUDE.md dead ref: $cr not in rules/"
      fi
    fi
  done
done

# =============================================================================
echo ""
echo "=== T5: Structural Sanity ==="
# =============================================================================
# CLAUDE.md line counts reasonable (non-trivial output)
for tdir in "$MIN_DIR" "$COM_DIR" "$MAX_DIR"; do
  tname=$(basename "$tdir" | sed 's/TKCC-CONF-//;s/-20[0-9]*//')
  if [ -f "$tdir/CLAUDE.md" ]; then
    lines=$(wc -l < "$tdir/CLAUDE.md" | tr -d ' ')
    if [ "$lines" -gt 50 ]; then
      pass "${tname} CLAUDE.md: ${lines} lines (substantive)"
    else
      fail "${tname} CLAUDE.md: only ${lines} lines (suspiciously short)"
    fi
  fi
done

# Report rule counts
min_rules=$(find "$MIN_DIR/rules" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
com_rules=$(find "$COM_DIR/rules" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
max_rules=$(find "$MAX_DIR/rules" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
[ "$min_rules" -ge 5 ] && pass "MIN rules: $min_rules (expected 7)" || fail "MIN rules: $min_rules (expected ≥5)"
[ "$com_rules" -ge 5 ] && pass "COMMON rules: $com_rules (expected 10)" || fail "COMMON rules: $com_rules (expected ≥5)"
[ "$max_rules" -ge 10 ] && pass "MAX rules: $max_rules (expected 18)" || fail "MAX rules: $max_rules (expected ≥10)"
[ "$max_rules" -ge "$com_rules" ] && pass "MAX rules ≥ COMMON rules (inheritance)" || fail "MAX rules < COMMON rules"

# =============================================================================
echo ""
echo "=== Results: $PASS passed, $FAIL failed ($TESTS tests) ==="
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "🔴 RED gate active — consistency violations found."
  exit 1
fi
echo "🟢 All structural checks green."
exit 0
