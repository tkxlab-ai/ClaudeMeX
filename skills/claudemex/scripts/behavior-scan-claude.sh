#!/usr/bin/env bash
# usage: behavior-scan-claude.sh --out-dir=DIR [--src=DIR]
# behavior-scan-claude.sh — reads ~/.claude/projects/*/*.jsonl, emits unified jsonl.
# Why python3 emits final JSON directly (no TSV intermediate):
# Real Claude assistant records contain multi-line content (markdown, code blocks).
# The previous TSV second-pass used IFS=$'\t' read which splits on embedded newlines,
# shifting field offsets and producing kind="" / cwd-in-ts corruption on real data.
# Same M-2 fix applied to Codex reader — now closed for Claude too.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/lib/behavior-schema.sh"

OUT_DIR=""
SRC_ROOT="${CLAUDE_HOME:-$HOME/.claude/projects}"

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

out="$OUT_DIR/claude.jsonl"
: > "$out"
chmod 600 "$out" 2>/dev/null || true

[ -d "$SRC_ROOT" ] || { echo "claude home empty: $SRC_ROOT" >&2; exit 0; }

# mktemp so concurrent runs never collide and stale files from prior crashes are avoided.
out_tmp=$(mktemp)
trap 'rm -f "$out_tmp"' EXIT

# python3 parses each file and emits final JSON directly to $out_tmp.
# Redact logic inlined — avoids spawning emit_jsonl_record (1 python3 fork per record).
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

path = sys.argv[1]
with open(path, 'r', encoding='utf-8', errors='replace') as fh:
    for ln, line in enumerate(fh, 1):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        # Real Claude schema uses top-level type=user|assistant + nested message.role/content.
        # Old fixture schema used flat role/content. Support both.
        rtype = r.get("type", "")
        msg = r.get("message", {}) or {}
        # kind: prefer nested message.role; fall back to top-level type; fall back to legacy r.get("role")
        kind = msg.get("role") or rtype or r.get("role") or "unknown"
        # Only emit user/assistant records (skip last-prompt, permission-mode, sidechain, etc.)
        if kind not in ("user", "assistant"):
            continue
        # text: nested message.content first; fall back to top-level (legacy fixture)
        text = msg.get("content") if msg else None
        if not text:
            text = r.get("content") or r.get("text") or ""
        # Real Claude message.content may be a list of segments — flatten to plain text
        if isinstance(text, list):
            text = "".join(
                seg.get("text", "") if isinstance(seg, dict) else str(seg)
                for seg in text
            )
        if not text:
            continue
        ts = r.get("timestamp") or r.get("ts") or ""
        sid = r.get("sessionId") or r.get("session_id") or ""
        cwd = redact(r.get("cwd") or "")
        print(json.dumps({
            "ts": ts, "tool": "claude", "kind": kind, "text": text,
            "cwd": cwd, "session_id": sid,
        }, ensure_ascii=False, separators=(",", ":")))
PY
done < <(find -P "$SRC_ROOT" -type f -name '*.jsonl' -mtime -30 -print0 2>/dev/null)

# Output is already final JSON — move to destination.
cat "$out_tmp" > "$out"

validate_schema < "$out" >&2 || { echo "schema validation failed" >&2; exit 1; }
echo "✓ claude.jsonl: $(wc -l < "$out") records"
