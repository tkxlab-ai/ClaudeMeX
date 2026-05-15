#!/usr/bin/env bash
# install.sh — install the ClaudeMeX skill into the user's Claude Code config.
#
# This is a thin wrapper that does TWO things:
#   1. Copies the bundled `TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md` to a
#      well-known location so the user can paste it into a Claude Code
#      session at any time.
#   2. Stages the helper scripts (redact-scan / structural-gate / deploy) so
#      they are executable from a stable path.
#
# It does NOT modify `~/.claude/CLAUDE.md` itself — that is the user's choice
# to make after running the generator interactively. Re-running install.sh
# is idempotent.
#
# Usage:
#   bash install.sh             # install to ~/.claude/skills/claudemex/
#   PREFIX=/opt/claudemex bash install.sh
#   bash install.sh --uninstall # remove the installed copy

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.claude/skills/claudemex}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=0
FORCE=0

uninstall() {
  if [ ! -d "$PREFIX" ]; then
    echo "ClaudeMeX is not installed at $PREFIX (nothing to remove)"
    exit 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] would: rm -rf $PREFIX"
    exit 0
  fi
  rm -rf "$PREFIX"
  echo "✅ Removed $PREFIX"
}

# Resolve flags. Accept any order; flags can co-occur with --uninstall.
ACTION="install"
for arg in "$@"; do
  case "$arg" in
    --uninstall|-u) ACTION="uninstall" ;;
    --dry-run)      DRY_RUN=1 ;;
    --force|-f)     FORCE=1 ;;
    --help|-h)
      cat <<EOF
install.sh — install / uninstall ClaudeMeX

  bash install.sh              install to \$PREFIX (default: ~/.claude/skills/claudemex/)
  bash install.sh --dry-run    print actions without running them
  bash install.sh --force      overwrite \$PREFIX even if non-empty (no prompt)
  bash install.sh --uninstall  remove the installed copy
  bash install.sh --help       show this help
  PREFIX=/path bash install.sh override install location
EOF
      exit 0
      ;;
    *)
      echo "Unknown flag: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

if [ "$ACTION" = "uninstall" ]; then
  uninstall
fi

# Block install into a populated PREFIX unless --force.
# In dry-run mode skip the gate so users can inspect actions without --force.
if [ "$DRY_RUN" -ne 1 ] && [ -d "$PREFIX" ] \
   && [ -n "$(ls -A "$PREFIX" 2>/dev/null)" ] && [ "$FORCE" -ne 1 ]; then
  echo "⚠️  $PREFIX exists and is not empty. Re-run with --force to overwrite, or pass a different PREFIX." >&2
  exit 1
fi

# `run` invokes its argv directly (no eval) so paths with spaces survive.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    echo
  else
    "$@"
  fi
}

# --force semantics: replace any existing install completely so removed files
# from prior versions don't linger alongside new ones.
if [ "$FORCE" -eq 1 ] && [ "$DRY_RUN" -ne 1 ] && [ -d "$PREFIX" ]; then
  rm -rf "$PREFIX"
fi
run mkdir -p "$PREFIX"
# The generator prompt — the canonical artefact users feed to Claude Code.
# Source repo layout has it at root; gitx-release release bundles flatten
# assets/ from skills/<name>/, so it lives in $SCRIPT_DIR/assets/ there.
PROMPT_SRC=""
for cand in \
  "$SCRIPT_DIR/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md" \
  "$SCRIPT_DIR/assets/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md" \
  "$SCRIPT_DIR/skills/claudemex/assets/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md"; do
  if [ -f "$cand" ]; then
    PROMPT_SRC="$cand"
    break
  fi
done
if [ -z "$PROMPT_SRC" ]; then
  echo "❌ Cannot find TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md under $SCRIPT_DIR" >&2
  echo "   Looked in: ./, ./assets/, ./skills/claudemex/assets/" >&2
  echo "   This bundle may be incomplete — please re-download." >&2
  exit 1
fi
run cp "$PROMPT_SRC" "$PREFIX/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md"
# Helper scripts (release toolchain — useful when curating outputs)
run mkdir -p "$PREFIX/scripts"
for s in redact-scan.sh structural-gate.sh deploy.sh; do
  if [ -f "$SCRIPT_DIR/scripts/$s" ]; then
    run cp "$SCRIPT_DIR/scripts/$s" "$PREFIX/scripts/$s"
    run chmod +x "$PREFIX/scripts/$s"
  fi
done
# Skill metadata. In the source repo it lives under skills/claudemex/.
# In a release bundle, gitx-release flatten places it at $SCRIPT_DIR/.
for d in SKILL.md VERSION; do
  if [ -f "$SCRIPT_DIR/$d" ]; then
    run cp "$SCRIPT_DIR/$d" "$PREFIX/"
  elif [ -f "$SCRIPT_DIR/skills/claudemex/$d" ]; then
    run cp "$SCRIPT_DIR/skills/claudemex/$d" "$PREFIX/"
  fi
done
# Bundled docs (live at repo root)
for d in README.md INSTALL.md LICENSE CONTRIBUTING.md TEST-SCENARIOS.md; do
  if [ -f "$SCRIPT_DIR/$d" ]; then
    run cp "$SCRIPT_DIR/$d" "$PREFIX/"
  fi
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] complete — nothing actually written"
  exit 0
fi
echo "✅ ClaudeMeX installed at $PREFIX"
echo "   Generator prompt: $PREFIX/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md"
echo "   Helper scripts:   $PREFIX/scripts/"
echo ""
echo "Next: open the generator prompt and paste it into a Claude Code session."
