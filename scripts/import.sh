#!/usr/bin/env bash
# claudemex import — extract one or more export tarballs into ./outputs/.
# Companion to claudemex export; used as a transport fallback when
# Syncthing/Gitea is unavailable.
#
# Hardening (per Codex review of v1.1.0):
#   V1-3 reject symlink / hardlink / device / FIFO / socket entries by type
#   V4   reject control characters in entry names
#   V6   cap total uncompressed size at --max-bytes (default 100 MB)
#   V7   extract with --no-same-owner --no-same-permissions
#   V8   snapshot file to a private temp before preflight+extract (defeats
#        TOCTOU swap of the original input between the two operations)
#   V9-10  path traversal patterns rejected (covered by V1-3 + name patterns)
# Usage: claudemex import [--into=DIR] [--max-bytes=N] FILE [FILE...]

set -uo pipefail

# Defence-in-depth (Codex F3): pin PATH to system locations so a
# poisoned PATH cannot shadow tar/gzip/cp/scutil/etc.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

INTO="./outputs"
MAX_BYTES=$((100 * 1024 * 1024))   # 100 MiB cap on uncompressed size
declare -a FILES=()

for arg in "$@"; do
    case "$arg" in
        --into=*)      INTO="${arg#--into=}";;
        --max-bytes=*) MAX_BYTES="${arg#--max-bytes=}";;
        -h|--help)
            cat <<'USAGE'
Usage: claudemex import [--into=DIR] [--max-bytes=N] FILE [FILE...]

Extracts one or more claudemex export tarballs (gzipped) into --into
(default ./outputs/). Each tarball must contain only regular files /
directories with relative paths inside the target.

Options:
  --into=DIR       Extraction target (default: ./outputs)
  --max-bytes=N    Reject tarball whose total uncompressed size > N
                   (default: 104857600 = 100 MiB)

Rejected:
  * absolute paths and ".." traversal
  * symlinks, hardlinks, devices, FIFOs, sockets
  * control characters in entry names
  * uncompressed size beyond --max-bytes
USAGE
            exit 0;;
        *) FILES+=("$arg");;
    esac
done

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "❌ no input tarballs (pass at least one FILE)" >&2
    echo "Usage: claudemex import [--into=DIR] [--max-bytes=N] FILE [FILE...]" >&2
    exit 1
fi

# Codex D3 (round 2 + stop-time follow-up): --max-bytes must be a sane
# positive integer ≤ 10 GiB. Validation has THREE gates because bash `[`
# integer comparison silently truncates >19-digit values and emits a
# "integer expected" warning to stderr; without `-e`, execution continues
# past the truncation and the ceiling check becomes inert. We defeat that
# by capping LENGTH first (numeric form), then comparing.
MAX_BYTES_CEILING=$((10 * 1024 * 1024 * 1024))   # 10 GiB = 10737418240 (11 digits)
if ! [[ "$MAX_BYTES" =~ ^[0-9]+$ ]]; then
    echo "❌ invalid --max-bytes: $MAX_BYTES (must be a non-negative decimal integer)" >&2
    exit 1
fi
# Length cap defeats >19-digit overflow attacks. CEILING is 11 digits; any
# input longer than that necessarily exceeds it.
if [ "${#MAX_BYTES}" -gt 11 ]; then
    echo "❌ --max-bytes=$MAX_BYTES exceeds ceiling $MAX_BYTES_CEILING (10 GiB) — too many digits" >&2
    exit 1
fi
if [ "$MAX_BYTES" -le 0 ]; then
    echo "❌ invalid --max-bytes: $MAX_BYTES (must be positive integer)" >&2
    exit 1
fi
if [ "$MAX_BYTES" -gt "$MAX_BYTES_CEILING" ]; then
    echo "❌ --max-bytes=$MAX_BYTES exceeds ceiling $MAX_BYTES_CEILING (10 GiB)" >&2
    exit 1
fi

mkdir -p "$INTO" || { echo "❌ cannot create --into=$INTO" >&2; exit 1; }

# Cleanup snapshots on any exit
declare -a TMP_TARS=()
cleanup_tmps() {
    local t
    for t in "${TMP_TARS[@]:-}"; do
        [ -n "$t" ] && rm -f "$t" 2>/dev/null
    done
}
trap cleanup_tmps EXIT

# preflight_tar TARBALL
# Pass 1 (tar -tvzf): reject by entry type, accumulate uncompressed size.
# Pass 2 (tar -tzf):  reject by name (path traversal + control chars).
# Returns 0 on safe, 1 on rejection.
preflight_tar() {
    local f="$1"
    local line type

    # Pass 1a: reject by entry type (verbose listing). Column for mode is
    # always the first whitespace-separated field on both BSD and GNU tar,
    # and its first character is the entry type.
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        type="${line:0:1}"
        case "$type" in
            l|L) echo "❌ '$f': symlink entry not allowed" >&2; return 1;;
            h|H) echo "❌ '$f': hardlink entry not allowed" >&2; return 1;;
            b|c|p|s|D)
                echo "❌ '$f': special entry type '$type' not allowed" >&2; return 1;;
        esac
    done < <(tar -tvzf "$f" 2>/dev/null)

    # Pass 1b: cap total uncompressed size. We read at most MAX_BYTES+1 bytes
    # so this short-circuits on huge archives instead of decompressing all.
    # gzip -dc | head -c is portable across BSD and GNU userland.
    local actual
    actual=$(gzip -dc -- "$f" 2>/dev/null | head -c $((MAX_BYTES + 1)) | wc -c | tr -d ' ')
    if [ -z "$actual" ] || ! [[ "$actual" =~ ^[0-9]+$ ]]; then
        echo "❌ '$f': cannot determine uncompressed size (corrupt gzip?)" >&2
        return 1
    fi
    if [ "$actual" -gt "$MAX_BYTES" ]; then
        echo "❌ '$f': uncompressed size exceeds cap $MAX_BYTES (use --max-bytes to override)" >&2
        return 1
    fi

    # Codex D1: filenames containing newline (\x0A) get split by `read` into
    # two records, each of which individually passes the per-record control-
    # char check. Detect by comparing entry counts: tar -tzf counts lines
    # (1 line per name, except names with embedded \n produce extra lines),
    # while tar -tvzf prints one line per entry regardless of name. Mismatch
    # ⇒ at least one name contains \n, reject the archive.
    local count_names count_entries
    count_names=$(tar -tzf "$f" 2>/dev/null | wc -l | tr -d ' ')
    count_entries=$(tar -tvzf "$f" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count_names" != "$count_entries" ]; then
        echo "❌ '$f': entry-name count ($count_names) differs from entry count ($count_entries)" >&2
        echo "    one or more filenames likely contain newline characters" >&2
        return 1
    fi

    local entry
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        # Control characters (incl. \t, \r, DEL) — names containing them
        # are almost certainly an attack or corrupted archive. Newline (\n)
        # is filtered separately above by entry-count comparison since the
        # `read` loop here can't see it.
        case "$entry" in
            *[$'\001'-$'\037'$'\177']*)
                echo "❌ '$f': control character in entry name" >&2; return 1;;
        esac
        # Path-traversal patterns
        case "$entry" in
            /*) echo "❌ '$f': absolute path: $entry" >&2; return 1;;
            *../*|../*|*/..|..)
                echo "❌ '$f': '..' traversal: $entry" >&2; return 1;;
            ./../*|./..)
                echo "❌ '$f': './..' traversal: $entry" >&2; return 1;;
        esac
    done < <(tar -tzf "$f" 2>/dev/null)
}

for f in "${FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "❌ not a file: $f" >&2
        exit 1
    fi

    # Snapshot to a private location before preflight + extract. This
    # defeats a TOCTOU attacker who can race a rename of $f between the
    # check and the use.
    #
    # Portable mktemp: explicit template path. Both BSD (macOS) mktemp and
    # GNU mktemp accept "DIR/PREFIX.XXXXXXXX" form. BSD `mktemp -t prefix`
    # is NOT a template (treats prefix literally and appends its own
    # suffix), and GNU `mktemp -t prefix` requires ≥3 X's in the prefix,
    # so neither -t form is portable. Use the explicit path form instead.
    tmp_tar=$(mktemp "${TMPDIR:-/tmp}/claudemex-import.XXXXXXXX") \
        || { echo "❌ mktemp failed" >&2; exit 1; }
    TMP_TARS+=("$tmp_tar")

    if ! cp -- "$f" "$tmp_tar"; then
        echo "❌ cannot snapshot $f" >&2
        exit 1
    fi
    if ! preflight_tar "$tmp_tar"; then
        echo "❌ refusing to extract $f (rejected by preflight)" >&2
        exit 1
    fi
    # --no-same-owner + --no-same-permissions: discard archive's owner /
    # mode bits (incl. setuid/setgid). Extracted files end up owned by
    # the current user with default umask-derived modes.
    if ! tar --no-same-owner --no-same-permissions -C "$INTO" -xzf "$tmp_tar"; then
        echo "❌ tar extraction failed for $f" >&2
        exit 1
    fi
    echo "✓ imported $f → $INTO/"
done
