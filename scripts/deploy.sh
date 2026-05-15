#!/usr/bin/env bash
# TKCC deploy.sh — Deploy generated tier configs
# Usage: bash deploy.sh <MIN|COMMON|MAX> <target-dir> [--base <outputs-path>]
# Exit: 0=success, 1=failure, 2=bad args
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TIER="${1:-}" TARGET="${2:-}" BASE="" FORCE=0
shift 2 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in --base) BASE="$2"; shift 2;; --force) FORCE=1; shift;; *) shift;; esac
done

[ -z "$TIER" ] && { echo "Usage: deploy.sh <MIN|COMMON|MAX> <target-dir>" >&2; exit 2; }
[ -z "$TARGET" ] && { echo "Usage: deploy.sh <MIN|COMMON|MAX> <target-dir>" >&2; exit 2; }
case "$TIER" in MIN|COMMON|MAX) ;; *) echo "Error: tier must be MIN, COMMON, or MAX." >&2; exit 2;; esac

# Resolve and validate target directory
mkdir -p "$TARGET" 2>/dev/null || { echo "Error: cannot create target-dir: $TARGET" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)" || { echo "Error: target-dir is not accessible: $TARGET" >&2; exit 1; }
case "$TARGET" in /*) ;; *) echo "Error: target-dir resolved to non-absolute path." >&2; exit 1;; esac

# Safety: reject deployment to critical system directories
case "$TARGET" in
  /|/usr|/usr/*|/etc|/etc/*|/System|/System/*|/Library|/Library/*|/Applications|/Applications/*)
    echo "Error: target-dir must not be a system directory. Use $HOME/.claude/ or a project-local dir." >&2
    exit 1 ;;
esac

BASE="${BASE:-$PROJECT_ROOT/outputs}"
[ ! -d "$BASE" ] && { echo "Error: outputs dir not found: $BASE" >&2; exit 1; }

# Backup existing CLAUDE.md before overwrite, unless --force was passed.
if [ -f "$TARGET/CLAUDE.md" ] && [ "$FORCE" -ne 1 ]; then
  cp "$TARGET/CLAUDE.md" "$TARGET/CLAUDE.md.bak" 2>/dev/null || true
fi

PFX="${CCG_PREFIX:-CLAUDE-CONF}"
match="" max_date=""
for dir in "$BASE"/${PFX}-${TIER}-*; do
  [ -d "$dir" ] || continue
  d="$(basename "$dir")"
  d_date="${d##*-}"
  case "$d_date" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])
    if [ -z "$max_date" ] || [ "$d_date" \> "$max_date" ]; then
      max_date="$d_date"; match="$dir"; fi ;; esac
done
[ -z "$match" ] && { echo "Error: no outputs found for tier $TIER (looked for ${PFX}-${TIER}-* under $BASE; set CCG_PREFIX to override)" >&2; exit 1; }

mkdir -p "$TARGET/rules"
[ -f "$match/CLAUDE.md" ] || { echo "Error: CLAUDE.md not found" >&2; exit 1; }
cp "$match/CLAUDE.md" "$TARGET/CLAUDE.md"
echo "  CLAUDE.md → $TARGET/CLAUDE.md"
rule_count=0
for rule in "$match"/rules/*.md; do
  [ -f "$rule" ] || continue
  cp "$rule" "$TARGET/rules/$(basename "$rule")"
  echo "  rules/$(basename "$rule")"
  rule_count=$((rule_count + 1))
done
[ ! -f "$TARGET/CLAUDE.md" ] && { echo "Error: CLAUDE.md missing after deploy" >&2; exit 1; }
[ "$rule_count" -lt 1 ] && { echo "Error: no rules deployed" >&2; exit 1; }
echo "Deployed $TIER: CLAUDE.md + $rule_count rule(s) → $TARGET"
