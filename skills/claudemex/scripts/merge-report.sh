#!/usr/bin/env bash
# claudemex merge-report — re-print merge / drift reports for an existing
# merged/<YYYY-WW>/ directory without re-running the merge algorithm.
# Usage: claudemex merge-report [--week=YYYY-WW] [--dir=PATH] [--diff-only]

set -uo pipefail

# Defence-in-depth (Codex F3): pin PATH to system locations so a
# poisoned PATH cannot shadow tar/gzip/cp/scutil/etc.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

WEEK=""
DIFF_ONLY=0
DIR=""
for arg in "$@"; do
    case "$arg" in
        --week=*)    WEEK="${arg#--week=}";;
        --dir=*)     DIR="${arg#--dir=}";;
        --diff-only) DIFF_ONLY=1;;
        -h|--help)
            cat <<'USAGE'
Usage: claudemex merge-report [--week=YYYY-WW] [--dir=PATH] [--diff-only]

Re-prints the reports under merged/<YYYY-WW>/ (or --dir=PATH for an
out-of-tree merge output). Default --week is the current ISO week.

  --diff-only   print only drift-report.md (skip the merge summary)

Exit codes:
  0  success
  1  no merged dir found / missing reports
USAGE
            exit 0;;
        *) echo "❌ unknown arg: $arg" >&2; exit 1;;
    esac
done

if [ -z "$DIR" ]; then
    [ -z "$WEEK" ] && WEEK=$(date +%G-W%V)
    DIR="merged/$WEEK"
fi

if [ ! -d "$DIR" ]; then
    echo "❌ no merge dir at: $DIR" >&2
    exit 1
fi

MERGE_REPORT="$DIR/merge-report.md"
DRIFT_REPORT="$DIR/drift-report.md"

if [ "$DIFF_ONLY" -eq 1 ]; then
    [ -f "$DRIFT_REPORT" ] || { echo "❌ no drift-report.md in $DIR" >&2; exit 1; }
    cat "$DRIFT_REPORT"
else
    [ -f "$MERGE_REPORT" ] || { echo "❌ no merge-report.md in $DIR" >&2; exit 1; }
    cat "$MERGE_REPORT"
    if [ -f "$DRIFT_REPORT" ]; then
        echo
        echo "==="
        echo
        cat "$DRIFT_REPORT"
    fi
fi
