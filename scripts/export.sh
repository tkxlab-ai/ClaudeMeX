#!/usr/bin/env bash
# claudemex export — package this host's most recent ClaudeMeX run as a tarball.
# Used as a transport fallback when Syncthing/Gitea is unavailable.
# Usage: claudemex export [--out=FILE] [--from=DIR]

set -uo pipefail

# Defence-in-depth (Codex F3): pin PATH to system locations so a
# poisoned PATH cannot shadow tar/gzip/cp/scutil/etc.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

OUT=""
FROM="./outputs"
for arg in "$@"; do
    case "$arg" in
        --out=*)  OUT="${arg#--out=}";;
        --from=*) FROM="${arg#--from=}";;
        -h|--help)
            cat <<'USAGE'
Usage: claudemex export [--out=FILE] [--from=DIR]

Packages this host's most-recent <host>-<ts>/ run from --from (default
./outputs/) into a gzipped tarball. Use claudemex import on the merge
node to extract.

Default --out: claudemex-export-<host>-<ts>.tar.gz
USAGE
            exit 0;;
        *) echo "unknown arg: $arg" >&2; exit 1;;
    esac
done

HOST=$(scutil --get LocalHostName 2>/dev/null | tr '[:upper:]' '[:lower:]')
[ -z "$HOST" ] && HOST=$(hostname -s | tr '[:upper:]' '[:lower:]')

# Pick the most recent <host>-<ts>/ directory matching this host
LATEST=""
for d in "$FROM"/${HOST}-*/; do
    [ -d "$d" ] || continue
    [ -f "$d/run-meta.yaml" ] || continue
    if [ -z "$LATEST" ] || [[ "$d" > "$LATEST" ]]; then LATEST="$d"; fi
done

if [ -z "$LATEST" ]; then
    echo "❌ no ${FROM}/${HOST}-*/ run found" >&2
    exit 1
fi

TS=$(basename "$LATEST" | sed -E "s/^${HOST}-//")
[ -z "$OUT" ] && OUT="claudemex-export-${HOST}-${TS}.tar.gz"

tar -C "$FROM" -czf "$OUT" "$(basename "$LATEST")"
echo "✓ exported $LATEST → $OUT"
