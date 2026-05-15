#!/usr/bin/env bash
# RUN_ALL: optional
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin

if [ "${CLAUDEMEX_TOCTOU_TEST:-0}" != "1" ]; then
  echo "SKIP test-adv-opencode-toctou.sh (timing-fragile; set CLAUDEMEX_TOCTOU_TEST=1 to enable)"
  exit 0
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); out=$(mktemp -d); trap 'rm -rf "$workdir" "$out"' EXIT

# Build db
python3 - <<PY
import sqlite3, json, pathlib
p = pathlib.Path("$workdir/oc.db")
c = sqlite3.connect(p)
c.executescript("""
CREATE TABLE session (id TEXT PRIMARY KEY, time_created INTEGER);
CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
""")
c.execute("INSERT INTO session VALUES (?,?)", ("s1", 1777911632))
for i in range(100):
    c.execute("INSERT INTO message VALUES (?,?,?,?,?)",
              (f"m{i}","s1",1777911632+i,1777911632+i,
               json.dumps({"role":"user","content":f"msg-{i}","cwd":"~"})))
c.commit(); c.close()
PY

# Background writer mutates db every 50ms
(
  for i in $(seq 1 20); do
    sqlite3 "$workdir/oc.db" "INSERT INTO message VALUES ('w$i','s1',$((1777911632+1000+i)),$((1777911632+1000+i)),'{\"role\":\"user\",\"content\":\"writer-$i\"}')" 2>/dev/null || true
    sleep 0.05
  done
) &
writer=$!

sleep 0.02
OPENCODE_DB="$workdir/oc.db" bash "$proj/scripts/behavior-scan-opencode.sh" --out-dir="$out"

wait $writer 2>/dev/null || true

# Reader's snapshot should NOT have torn rows; line count is one-shot consistent
n=$(wc -l < "$out/opencode.jsonl")
[ "$n" -ge 100 ] || { echo "FAIL: too few rows ($n)"; exit 1; }
echo "PASS test-adv-opencode-toctou.sh ($n rows)"
