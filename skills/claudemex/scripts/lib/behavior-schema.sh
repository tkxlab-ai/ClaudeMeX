#!/usr/bin/env bash
# behavior-schema.sh — shared helpers for behavior-scan-*.sh readers.
# Sourced as a library; caller owns strict-mode flags.

redact_cwd() {
  local cwd="$1"
  local self
  self=$(whoami)
  # Self paths first (macOS + Linux); (/|$) handles trailing-slash and end-of-string.
  # Using sed instead of bash ${//} because bash 5.3 mishandles escaped-slash patterns.
  cwd=$(echo "$cwd" | sed -E "s#/Users/$self(/|$)#~\1#g; s#/home/$self(/|$)#~\1#g")
  # Other users on macOS / Linux → <user>:~/...
  cwd=$(echo "$cwd" | sed -E 's#^/Users/([a-zA-Z0-9_-]+)(/|$)#<\1>:~\2#g; s#^/home/([a-zA-Z0-9_-]+)(/|$)#<\1>:~\2#g')
  echo "$cwd"
}

# emit_jsonl_record TS TOOL KIND TEXT CWD SESSION_ID
# Emits a single JSON object on stdout following the unified schema.
# Why python3: json.dumps gives free escaping for embedded quotes and unicode.
# ensure_ascii=False preserves 中文 reliably. separators=(",":) produces compact
# form matching the expected literal in tests.
emit_jsonl_record() {
  python3 - "$@" <<'PY'
import json, sys
ts, tool, kind, text, cwd, sid = sys.argv[1:7]
print(json.dumps({
    "ts": ts, "tool": tool, "kind": kind,
    "text": text, "cwd": cwd, "session_id": sid,
}, ensure_ascii=False, separators=(",",":")))
PY
}

# validate_schema: reads jsonl from stdin, exits 1 on first invalid line
# (or exits 0 if all lines valid). Required fields: ts,tool,kind,text,cwd,session_id.
# tool must be one of: claude,codex,gemini,opencode.
# Why capture stdin first: `python3 - <<'PY'` heredoc shadows the pipe's stdin, so
# we read the pipe into a variable and pass it via -c with sys.argv, avoiding the conflict.
validate_schema() {
  local input
  input=$(cat)
  python3 -c '
import json, sys
required = {"ts","tool","kind","text","cwd","session_id"}
allowed_tools = {"claude","codex","gemini","opencode"}
for ln, line in enumerate(sys.argv[1].splitlines(), 1):
    line = line.strip()
    if not line:
        continue
    try:
        rec = json.loads(line)
    except Exception as e:
        sys.stderr.write(f"line {ln}: invalid JSON: {e}\n")
        sys.exit(1)
    missing = required - rec.keys()
    if missing:
        sys.stderr.write(f"line {ln}: missing fields: {missing}\n")
        sys.exit(1)
    if rec["tool"] not in allowed_tools:
        t = rec["tool"]
        sys.stderr.write(f"line {ln}: invalid tool: {t}\n")
        sys.exit(1)
' "$input"
}
