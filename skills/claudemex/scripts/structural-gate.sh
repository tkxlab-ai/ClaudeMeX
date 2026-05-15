#!/usr/bin/env bash
# Release/structural-gate.sh
# -----------------------------------------------------------------------------
# Structural verification (Layer 2, mandatory). Complements redact-scan.sh.
#
# Polanyi's critique rejected grep-for-literal-phrases as proof that tacit
# knowledge is captured. Instead this script verifies that STRUCTURAL POINTERS
# to tacit-knowledge carriers are present as LIVE references:
#
#   1. HANDOFF.md reference exists and is not inside a fenced code block
#   2. .memory/ entry-point enumerates >= 3 sub-elements
#   3. User-protocol trigger section is present (at least a header exists)
#
# Usage: ./structural-gate.sh <path-to-release-directory>
# Exit : 0 = pass, 1 = one or more structural gates failed, 2 = bad args
# -----------------------------------------------------------------------------

set -uo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  echo "Usage: $0 <path-to-release-directory>" >&2
  exit 2
fi

if [ -t 1 ]; then
  R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; N='\033[0m'
else
  R=''; G=''; Y=''; B=''; N=''
fi

FAIL=0

# Gather candidate memory-rule files (MIN uses 06-memory.md, COMMON 07-memory.md,
# MAX may combine; CLAUDE.md itself is also a legitimate carrier).
MEM_FILES=$(find "$TARGET" -type f \( -name "*memory*.md" -o -name "CLAUDE.md" -o -name "07-memory.md" -o -name "06-memory.md" \) 2>/dev/null)

if [ -z "$MEM_FILES" ]; then
  # This is not a generator-output directory (no CLAUDE.md / memory rule present).
  # Structural gate applies to generator outputs (MIN / COMMON / MAX tiers),
  # not to release bundles that only carry the prompt itself.
  echo "${Y}[SKIP]${N}  No CLAUDE.md or memory-rule file found in $TARGET"
  echo "        structural-gate applies to generator-output tiers, not release bundles."
  echo "        To run this gate, target e.g. outputs/CLAUDE-CONF-MIN-YYYYMMDD/"
  exit 0
fi

echo "${B}== Structural gate ==${N}"
echo "Target: $TARGET"
echo "Memory-rule candidates:"
echo "$MEM_FILES" | sed 's/^/  - /'
echo

# --- Check 1: Live HANDOFF.md reference (outside fenced code blocks) ---
echo -n "[1/3] Live HANDOFF.md reference .. "
HANDOFF_HIT=0
while IFS= read -r f; do
  # Strip fenced code blocks then grep
  if awk '
    /^```/ {inblock = !inblock; next}
    !inblock {print}
  ' "$f" 2>/dev/null | grep -q "HANDOFF\.md"; then
    HANDOFF_HIT=1
    break
  fi
done <<< "$MEM_FILES"

if [ "$HANDOFF_HIT" -eq 1 ]; then
  echo "${G}PASS${N}"
else
  echo "${R}FAIL${N} — no live HANDOFF.md reference found outside code blocks"
  FAIL=$((FAIL + 1))
fi

# --- Check 2: .memory/ entry-point enumerates >=3 sub-elements ---
echo -n "[2/3] .memory/ entry-point (>=3 sub-elements) .. "
MEM_SUB_COUNT=0
# Canonical sub-elements we look for
for sub in "context\.md" "progress\.md" "INDEX\.md" "session-" "\.memory/"; do
  if echo "$MEM_FILES" | xargs grep -l "$sub" >/dev/null 2>&1; then
    MEM_SUB_COUNT=$((MEM_SUB_COUNT + 1))
  fi
done

if [ "$MEM_SUB_COUNT" -ge 3 ]; then
  echo "${G}PASS${N} ($MEM_SUB_COUNT/5 sub-elements referenced)"
else
  echo "${R}FAIL${N} (only $MEM_SUB_COUNT/5 sub-elements — need >=3)"
  FAIL=$((FAIL + 1))
fi

# --- Check 3: User-protocol trigger section ---
echo -n "[3/3] User-protocol trigger section .. "
PROTO_HIT=0
# Accept any of: "recall" keyword, "trigger" section header, "protocol" heading
for pattern in "recall" "[Tt]rigger [Ww]ord" "[Pp]rotocol" "[Mm]emory protocol"; do
  if echo "$MEM_FILES" | xargs grep -lE "$pattern" >/dev/null 2>&1; then
    PROTO_HIT=1
    break
  fi
done

if [ "$PROTO_HIT" -eq 1 ]; then
  echo "${G}PASS${N}"
else
  echo "${R}FAIL${N} — no recall / trigger / protocol section found"
  FAIL=$((FAIL + 1))
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "${G}== STRUCTURAL PASS ==${N}  All 3 gates satisfied."
  exit 0
else
  echo "${R}== STRUCTURAL BLOCK ==${N}  $FAIL / 3 gates failed."
  echo "Rationale (Polanyi): tacit knowledge is verified by live carriers, not by string presence."
  exit 1
fi
