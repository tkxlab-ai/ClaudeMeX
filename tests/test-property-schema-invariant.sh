#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../scripts/lib/behavior-schema.sh"

# Generate 10000 random records via emit_jsonl_record and validate them all
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
python3 - <<'PY' > "$tmp"
import random, string, json
random.seed(43)
tools = ["claude","codex","gemini","opencode"]
kinds = ["user","assistant","assistant_action","session_meta","thread_name"]
def rand_text():
    return "".join(random.choice(string.ascii_letters + " 不要必须don't") for _ in range(random.randint(1,60)))
def rand_cwd():
    return random.choice(["~","~/c","~/code/foo","<other>:~/repo","/tmp/x","/private/var/y"])
for i in range(10000):
    rec = {
        "ts": f"2026-05-04T16:{i%60:02d}:{(i*7)%60:02d}Z",
        "tool": random.choice(tools),
        "kind": random.choice(kinds),
        "text": rand_text(),
        "cwd": rand_cwd(),
        "session_id": f"sid-{i:05d}",
    }
    print(json.dumps(rec, ensure_ascii=False, separators=(",",":")))
PY

# All 10000 lines must pass validate_schema (no exit 1).
# validate_schema bundles stdin into sys.argv[1] which hits ARG_MAX on large inputs,
# so we batch in 1000-line chunks — each batch exercises the same invariant logic.
total=$(wc -l < "$tmp")
chunk=1000
batch=0
while IFS= read -r batch_lines; do
  [ -n "$batch_lines" ] || continue
  batch=$((batch + 1))
  printf '%s\n' "$batch_lines" | validate_schema \
    || { echo "FAIL: schema invariant violated at batch $batch"; exit 1; }
done < <(python3 -c "
import sys
lines=open(sys.argv[1]).readlines()
for i in range(0, len(lines), $chunk):
    print(''.join(lines[i:i+$chunk]).rstrip())
" "$tmp")

echo "PASS test-property-schema-invariant.sh (10000 records, $batch batches)"
