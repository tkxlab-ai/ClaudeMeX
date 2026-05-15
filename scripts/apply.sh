#!/usr/bin/env bash
# claudemex apply — deploy a merge kernel to the current machine.
# Default behavior is dry-run (prints diff, does not write).
# Pass --apply to actually write the target file (with backup unless --force).
# Usage: claudemex apply --kernel=PATH [--target=claude] [--apply] [--force] [--target-file=PATH]

set -uo pipefail

# Defence-in-depth (Codex F3): pin PATH to system locations so a
# poisoned PATH cannot shadow tar/gzip/cp/scutil/etc.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SELF_DIR/lib/meta-yaml.sh"
. "$SELF_DIR/lib/render-claude.sh"

G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; N_=$'\e[0m'

usage() {
    cat <<'USAGE'
Usage: claudemex apply --kernel=PATH [--target=claude|codex|opencode]
                       [--apply] [--force] [--target-file=PATH]

Deploy a merge kernel to this host's CLAUDE.md (or per-tool target).

Options:
  --kernel=PATH     Path to merged/<week>/ (or merged/latest/) — REQUIRED
  --target          Render target (default: claude). Phase 1: claude only;
                    codex/opencode return exit 99.
  --apply           Default off → dry-run prints diff but does not write.
                    With --apply: writes the target file (after backup unless --force).
  --force           Skip backup of existing target file.
  --target-file     Override default target path (used by tests).
                    Default: ~/.claude/CLAUDE.md
  -h, --help        Show this help

Exit codes:
  0  success
  1  invalid kernel / missing flags / unknown target
  2  this host has no per-machine-extension entry in this kernel
  3  backup target collision (rare: same-second invocation)
  99 Phase 2 target requested in Phase 1
USAGE
}

KERNEL=""; TARGET="claude"; APPLY=0; FORCE=0; TARGET_FILE=""; NO_OPENCODE_EXPORT=0
for arg in "$@"; do
    case "$arg" in
        --kernel=*)           KERNEL="${arg#--kernel=}";;
        --target=*)           TARGET="${arg#--target=}";;
        --target-file=*)      TARGET_FILE="${arg#--target-file=}";;
        --apply)              APPLY=1;;
        --force)              FORCE=1;;
        --no-opencode-export) NO_OPENCODE_EXPORT=1;;
        -h|--help)            usage; exit 0;;
        *) echo "${R}unknown arg:${N_} $arg" >&2; usage >&2; exit 1;;
    esac
done

if [ -z "$KERNEL" ]; then
    echo "${R}❌${N_} --kernel is required" >&2
    usage >&2
    exit 1
fi

if [ ! -d "$KERNEL/common-kernel" ] || [ ! -f "$KERNEL/common-kernel/kernel-meta.yaml" ]; then
    echo "${R}❌${N_} invalid kernel: $KERNEL (missing common-kernel/kernel-meta.yaml)" >&2
    exit 1
fi

case "$TARGET" in
    claude)             ;;
    codex|opencode)
        echo "${Y}⚠${N_}  --target=$TARGET is reserved for Phase 2 (not implemented in v1.1.x)" >&2
        exit 99
        ;;
    *)
        echo "${R}❌${N_} unknown --target=$TARGET" >&2
        exit 1
        ;;
esac

# Gotcha #6 advisory — ~/AGENTS.md symlink to Claude file causes OpenCode
# to load the same content twice (project + global fallback layers).
if [ -L "$HOME/AGENTS.md" ]; then
    link_tgt=$(readlink "$HOME/AGENTS.md")
    case "$link_tgt" in
        *"/.claude/CLAUDE.md")
            echo "⚠ $HOME/AGENTS.md → $link_tgt symlink detected." >&2
            echo "  This causes OpenCode to load the same content twice (project + global)." >&2
            echo "  Recommended: rm $HOME/AGENTS.md (Codex still reads $HOME/.codex/AGENTS.md)." >&2
            ;;
    esac
fi

# Resolve host
HOST=$(scutil --get LocalHostName 2>/dev/null | tr '[:upper:]' '[:lower:]')
[ -z "$HOST" ] && HOST=$(hostname -s | tr '[:upper:]' '[:lower:]')

# Codex E2: validate HOST against the same strict regex merge.sh uses.
# A user with admin rights who renamed LocalHostName to something like
# "../../outside" would otherwise smuggle path components into
# "$KERNEL/per-machine-extension/$HOST/..." downstream. Out of stated
# threat model (requires local admin), but cheap defence-in-depth.
HOST_RE='^[a-z0-9][a-z0-9._-]{0,62}$'
if ! [[ "$HOST" =~ $HOST_RE ]]; then
    echo "${R}❌${N_} resolved hostname '$HOST' is not a valid hostname (regex: $HOST_RE)" >&2
    echo "    refusing to use it as a path component" >&2
    exit 1
fi

# Default target file
if [ -z "$TARGET_FILE" ]; then
    TARGET_FILE="$HOME/.claude/CLAUDE.md"
fi

# Warn if this host has no per-machine-extension entry in this kernel
# (proceeds with common-kernel-only render; not a hard error per spec §10
#  revision — preview path should remain usable for new/unregistered hosts)
if [ ! -d "$KERNEL/per-machine-extension/$HOST" ]; then
    AVAIL_HOSTS=$(ls -1 "$KERNEL/per-machine-extension" 2>/dev/null | tr '\n' ' ')
    echo "${Y}⚠${N_}  host '$HOST' has no per-machine-extension in this kernel" >&2
    echo "    available extensions: ${AVAIL_HOSTS:-<none>}" >&2
    echo "    output will contain common-kernel only (no per-host extension)" >&2
fi

# Render to a tmp file first (always)
TMP_OUT=$(mktemp)
trap "rm -f '$TMP_OUT'" EXIT
render_claude_md "$KERNEL" "$HOST" "$TMP_OUT"

# Dry-run path: print diff, don't write
if [ "$APPLY" -eq 0 ]; then
    echo "${G}▸${N_} Dry-run: target=$TARGET_FILE host=$HOST"
    if [ -f "$TARGET_FILE" ]; then
        diff -u "$TARGET_FILE" "$TMP_OUT" || true
    else
        echo "${Y}(target does not exist; --apply would create)${N_}"
        echo "--- preview (first 40 lines) ---"
        head -40 "$TMP_OUT"
    fi
    echo
    echo "${G}✓${N_} dry-run complete; pass --apply to write"
    exit 0
fi

# Apply path: backup then write. Every filesystem op must succeed before
# we proceed; a silent backup/write failure would leave the target file
# in an inconsistent state without telling the user.
if [ -f "$TARGET_FILE" ] && [ "$FORCE" -eq 0 ]; then
    backup_path="${TARGET_FILE}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    # Codex E1: -e is false on a dangling symlink, which would let
    # cp follow the link and write to its target. Reject ANY existing
    # entry at backup_path — file, dir, OR symlink (dangling or not).
    if [ -e "$backup_path" ] || [ -L "$backup_path" ]; then
        echo "${R}❌${N_} backup target path is occupied (file/dir/symlink): $backup_path" >&2
        exit 3
    fi
    if ! cp "$TARGET_FILE" "$backup_path"; then
        echo "${R}❌${N_} backup failed: cp $TARGET_FILE → $backup_path" >&2
        exit 1
    fi
    if [ ! -f "$backup_path" ]; then
        echo "${R}❌${N_} backup verification failed: $backup_path missing post-cp" >&2
        exit 1
    fi
    echo "${G}✓${N_} backed up: $backup_path"
fi

if ! mkdir -p "$(dirname "$TARGET_FILE")"; then
    echo "${R}❌${N_} cannot create target dir: $(dirname "$TARGET_FILE")" >&2
    exit 1
fi
if ! cp "$TMP_OUT" "$TARGET_FILE"; then
    echo "${R}❌${N_} write failed: cp $TMP_OUT → $TARGET_FILE" >&2
    exit 1
fi
if [ ! -f "$TARGET_FILE" ]; then
    echo "${R}❌${N_} write verification failed: $TARGET_FILE missing post-cp" >&2
    exit 1
fi
echo "${G}✓${N_} wrote $TARGET_FILE (host=$HOST, kernel=$KERNEL)"

# v1.3 opportunistic OpenCode export — eliminates double-load when OpenCode
# falls back to ~/.claude/CLAUDE.md while ~/AGENTS.md is also a symlink to it.
# Will be replaced by per-tool render in v1.4.
if [ "$NO_OPENCODE_EXPORT" -eq 0 ]; then
    if ! mkdir -p "$HOME/.config/opencode"; then
        echo "${Y}⚠${N_}  opencode export: could not mkdir $HOME/.config/opencode (skipping)" >&2
    else
        oc_target="$HOME/.config/opencode/AGENTS.md"
        if [ -L "$oc_target" ]; then
            echo "${Y}⚠${N_}  refusing to write through symlink: $oc_target → $(readlink "$oc_target")" >&2
            echo "    Remove the symlink first (rm $oc_target) to enable opportunistic OpenCode export." >&2
        elif [ -e "$oc_target" ] && [ ! -w "$oc_target" ]; then
            echo "${Y}⚠${N_}  cannot write $oc_target (permission denied — file is read-only)" >&2
            echo "    Existing content preserved. Adjust permissions (chmod u+w) or remove file to enable export." >&2
        else
            {
                echo '<!-- claudemex v1.3 opportunistic export — identical to ~/.claude/CLAUDE.md, will diverge in v1.4 with per-tool dialect render -->'
                cat "$TARGET_FILE"
            } > "$oc_target"
            echo "${G}✓${N_} opencode export: $oc_target"
        fi
    fi
fi

exit 0
