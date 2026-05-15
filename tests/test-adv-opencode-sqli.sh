#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); out=$(mktemp -d); trap 'rm -rf "$workdir" "$out"' EXIT

# Build db with SQL-injection-style message.data
python3 - <<PY
import sqlite3, json, pathlib
p = pathlib.Path("$workdir/sqli.db")
c = sqlite3.connect(p)
c.executescript("""
CREATE TABLE session (id TEXT PRIMARY KEY, time_created INTEGER);
CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
""")
c.execute("INSERT INTO session VALUES (?,?)", ("s1", 1777911632))
c.execute("INSERT INTO message VALUES (?,?,?,?,?)",
          ("m1","s1",1777911632,1777911632,
           json.dumps({"role":"user","content":"'; DROP TABLE message; --","cwd":"~"})))
c.commit(); c.close()
PY
touch -t 202605110000 "$workdir/sqli.db"

OPENCODE_DB="$workdir/sqli.db" bash "$proj/scripts/behavior-scan-opencode.sh" --out-dir="$out"

# Tables intact after reader exits
remaining=$(sqlite3 "$workdir/sqli.db" ".tables")
echo "$remaining" | grep -q 'message' || { echo "FAIL: message table dropped"; exit 1; }
echo "PASS test-adv-opencode-sqli.sh"
