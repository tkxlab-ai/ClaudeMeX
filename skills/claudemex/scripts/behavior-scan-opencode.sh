#!/usr/bin/env bash
# usage: behavior-scan-opencode.sh --out-dir=DIR [--db=PATH]
# behavior-scan-opencode.sh — reads OpenCode opencode.db (SQLite), emits unified jsonl.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/lib/behavior-schema.sh"
OUT_DIR=""; DB="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"
while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir=*) OUT_DIR="${1#--out-dir=}";;
    --db=*)      DB="${1#--db=}";;
    *) echo "unknown: $1" >&2; exit 1;;
  esac; shift
done
[ -n "$OUT_DIR" ] || { echo "missing --out-dir" >&2; exit 1; }
mkdir -p "$OUT_DIR"; chmod 700 "$OUT_DIR" 2>/dev/null || true
out="$OUT_DIR/opencode.jsonl"; : > "$out"; chmod 600 "$out" 2>/dev/null || true

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "⚠ sqlite3 not found; OpenCode reader skipped (install sqlite3 for signal extraction)" >&2
  exit 0
fi
[ -f "$DB" ] || { echo "opencode db absent: $DB" >&2; exit 0; }

# ToCToU + WAL lock: copy db to tempfile so live opencode process can't
# mutate or lock our read. Explicit template path works on both BSD and GNU mktemp.
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/claudemex-opencode.XXXXXX")
chmod 700 "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
# Retry cp 3× with 100ms backoff — OpenCode may hold a WAL writer lock during a flush.
for attempt in 1 2 3; do
  if cp -P "$DB" "$tmpdir/oc.db" 2>/dev/null; then
    break
  fi
  if [ "$attempt" = "3" ]; then
    echo "⚠ opencode db copy failed after 3 attempts (live writer held lock?); skipping" >&2
    exit 0
  fi
  sleep 0.1
done

# Schema fingerprint check — bail if it's not the expected opencode shape.
tables=$(sqlite3 "$tmpdir/oc.db" ".tables" 2>/dev/null || echo "")
case " $tables " in
  *" session "*) ;;
  *) echo "⚠ opencode schema mismatch (no 'session' table)" >&2; exit 0;;
esac

# Write the Python parser to a tempfile so it can receive sqlite3 stdout
# via pipe without heredoc stealing stdin (plan-bug: heredoc + pipe stdin
# conflict — the heredoc wins, feeding Python code as data to python3).
cat > "$tmpdir/parse.py" <<'PY'
import json, sys, datetime, os, re
def redact(cwd):
    self = os.environ.get("USER","")
    if not cwd: return cwd
    if self:
        cwd = cwd.replace(f"/Users/{self}","~").replace(f"/home/{self}","~")
    cwd = re.sub(r"/Users/([a-zA-Z0-9_-]+)/", r"<\1>:~/", cwd)
    cwd = re.sub(r"/home/([a-zA-Z0-9_-]+)/",  r"<\1>:~/", cwd)
    return cwd
def emit(ts, kind, text, cwd, sid):
    print(json.dumps({"ts":ts,"tool":"opencode","kind":kind,"text":text,"cwd":cwd,"session_id":sid},
                     ensure_ascii=False, separators=(",",":")))
for line in sys.stdin:
    try:
        tc, sid, data = line.rstrip("\n").split("\t", 2)
    except ValueError:
        continue
    try:
        d = json.loads(data)
    except Exception:
        continue
    role = d.get("role","unknown")
    text = d.get("content") or d.get("text") or ""
    if isinstance(text, list): text = "".join(str(t) for t in text)
    cwd  = redact(d.get("cwd",""))
    try:
        iso = datetime.datetime.utcfromtimestamp(int(tc)).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        iso = ""
    emit(iso, role, text, cwd, sid)
PY

# Pipe sqlite3 tab-separated rows into python3 for JSON parsing + emit.
# Python does the cwd redaction inline since this pipeline doesn't use the
# bash redact_cwd path (the bash second-pass would collide with embedded
# tabs/newlines from the data column).
sqlite3 -separator $'\t' "$tmpdir/oc.db" \
  "SELECT time_created, session_id, data FROM message ORDER BY time_created" \
  2>/dev/null | python3 "$tmpdir/parse.py" >> "$out"

validate_schema < "$out" >&2 || true
echo "✓ opencode.jsonl: $(wc -l < "$out") records"
