#!/usr/bin/env bash
# usage: behavior-scan-codex.sh --out-dir=DIR [--src=DIR]
# behavior-scan-codex.sh — reads Codex rollout-*.jsonl sessions → unified schema JSONL.
# Codex session layout: $CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl
# Two record types: session_meta (session start, carries cwd + session_id) and
# event_msg (user_message / agent_message / user_input). Both normalised to unified schema.
#
# Why python3 emits final JSON directly (no TSV intermediate):
# Real Codex user_message payloads contain multi-line code blocks. The previous
# TSV second-pass used IFS=$'\t' read which splits on any newline inside text,
# corrupting all fields after the first embedded newline. M-2 from r1 review, now closed.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/behavior-schema.sh
. "$here/lib/behavior-schema.sh"

OUT_DIR=""
SRC_ROOT="${CODEX_HOME:-$HOME/.codex}"

while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir=*) OUT_DIR="${1#--out-dir=}";;
    --src=*)     SRC_ROOT="${1#--src=}";;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
  shift
done

[ -n "$OUT_DIR" ] || { echo "missing --out-dir" >&2; exit 1; }
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR" 2>/dev/null || true

out="$OUT_DIR/codex.jsonl"
: > "$out"
chmod 600 "$out" 2>/dev/null || true

sess_root="$SRC_ROOT/sessions"
[ -d "$sess_root" ] || { echo "codex sessions dir absent: $sess_root" >&2; exit 0; }

# mktemp so concurrent runs never collide and stale files from prior crashes are avoided.
out_tmp=$(mktemp)
trap 'rm -f "$out_tmp"' EXIT

# python3 parses each file and emits final JSON directly to $out_tmp.
# Redact logic is inlined (mirrors OpenCode reader pattern) — avoids spawning
# a separate process per record (emit_jsonl_record would cost ~1 fork per line).
while IFS= read -r -d '' f; do
  python3 - "$f" >> "$out_tmp" <<'PY'
import json, sys, os, re

def redact(cwd):
    self = os.environ.get("USER", "")
    if not cwd:
        return cwd
    if self:
        cwd = re.sub(rf"/Users/{re.escape(self)}(/|$)", r"~\1", cwd)
        cwd = re.sub(rf"/home/{re.escape(self)}(/|$)", r"~\1", cwd)
    cwd = re.sub(r"/Users/([a-zA-Z0-9_-]+)(/|$)", r"<\1>:~\2", cwd)
    cwd = re.sub(r"/home/([a-zA-Z0-9_-]+)(/|$)", r"<\1>:~\2", cwd)
    return cwd

def emit(ts, kind, text, cwd, sid):
    print(json.dumps({
        "ts": ts, "tool": "codex", "kind": kind, "text": text,
        "cwd": cwd, "session_id": sid,
    }, ensure_ascii=False, separators=(",", ":")))

path = sys.argv[1]
sid = ""
total = 0
bad = 0
with open(path, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        total += 1
        try:
            r = json.loads(line)
        except Exception:
            bad += 1
            continue
        t  = r.get("type", "")
        ts = r.get("timestamp", "")
        pl = r.get("payload") or {}
        if t == "session_meta":
            # Session boundary: record id + cwd for all lines in this file.
            sid = pl.get("id", "") or sid
            cwd = redact(pl.get("cwd", ""))
            emit(ts, "session_meta", "<session start>", cwd, sid)
        elif t == "event_msg":
            sub = pl.get("type", "")
            # Real Codex uses user_message / agent_message; legacy fixtures used user_input.
            if sub in ("user_input", "user_message"):
                kind = "user"
            elif sub == "agent_message":
                kind = "assistant"
            elif sub == "assistant_action":
                kind = "assistant_action"
            else:
                # Skip token_count, task_started, task_complete, thread_name_updated, etc.
                continue
            # Real Codex stores body as payload.message; legacy was payload.text.
            text = pl.get("text") or pl.get("message") or ""
            if isinstance(text, list):
                text = "".join(str(x) for x in text)
            if not text:
                continue
            emit(ts, kind, text, "", sid)
# Per-file corruption summary on stderr — lets downstream detect Codex jsonl drift.
sys.stderr.write(f"corruption_rate={bad}/{total}\n")
PY
# Defence-in-depth: explicit blacklist for auth.json + installation_id.
# Current glob is rollout-*.jsonl under sessions/, but if someone widens the
# walk later we still skip credentials.
done < <(find -P "$sess_root" -type f -name 'rollout-*.jsonl' \
                ! -path '*/auth.json' ! -name 'installation_id' \
                -mtime -30 -print0 2>/dev/null)

# session_index.jsonl is a sibling at SRC_ROOT root (NOT under sessions/).
# It carries thread_name per session — emit each row as a kind="thread_name" record.
sidx="$SRC_ROOT/session_index.jsonl"
if [ -f "$sidx" ]; then
  python3 - "$sidx" >> "$out_tmp" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8', errors='replace') as fh:
    for line in fh:
        line = line.strip()
        if not line: continue
        try: r = json.loads(line)
        except Exception: continue
        sid = r.get("session_id", "")
        name = r.get("thread_name", "")
        ts = r.get("created_at", "")
        if not (sid and name): continue
        print(json.dumps({
            "ts": ts, "tool": "codex", "kind": "thread_name",
            "text": name, "cwd": "", "session_id": sid,
        }, ensure_ascii=False, separators=(",", ":")))
PY
fi

if [ ! -s "$out_tmp" ]; then
  # No files found or all empty — output remains empty; validate_schema handles empty input.
  echo "codex: no records in the last 30 days" >&2
  exit 0
fi

# Output is already final JSON — move to destination.
cat "$out_tmp" > "$out"

# Validate output against unified schema; write diagnostics to stderr so they
# don't pollute the JSONL output file.
validate_schema < "$out" >&2 || { echo "schema validation failed" >&2; exit 1; }

echo "✓ codex.jsonl: $(wc -l < "$out") records"
