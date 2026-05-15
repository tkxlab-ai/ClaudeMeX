#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
file="$proj/evals/evals.json"
[ -f "$file" ] || { echo "FAIL: evals/evals.json missing"; exit 1; }
python3 -m json.tool < "$file" > /dev/null || { echo "FAIL: invalid JSON"; exit 1; }
python3 - "$file" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("skill_name") == "claudemex", "skill_name mismatch"
evals = d.get("evals", [])
assert isinstance(evals, list) and len(evals) >= 6, f"evals[] must have >=6 entries, got {len(evals)}"
trig = sum(1 for e in evals if e.get("should_trigger") is True)
notrig = sum(1 for e in evals if e.get("should_trigger") is False)
assert trig >= 3, f"need >=3 should_trigger=true, got {trig}"
assert notrig >= 3, f"need >=3 should_trigger=false, got {notrig}"
for e in evals:
    for k in ("id","prompt","should_trigger","expected_output","files"):
        assert k in e, f"eval {e.get('id')} missing field {k}"
    assert isinstance(e["prompt"], str) and e["prompt"], "prompt must be non-empty string"
print("evals.json schema valid")
PY
echo "PASS test-evals-schema.sh"
