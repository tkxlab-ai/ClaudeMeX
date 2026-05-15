#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../scripts/lib/behavior-schema.sh"

# Generate 1000 random cwd paths and pipe through redact_cwd
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
python3 - <<'PY' > "$tmp"
import random
random.seed(42)
forms = [
  lambda u: f"/Users/{u}/code/{random.randint(1,99)}",
  lambda u: f"/home/{u}/repo",
  lambda u: f"/tmp/cache/{u}.log",
  lambda u: f"/private/var/folders/x/{u}",
  lambda u: f"/Users/{u}/Users/inception",
]
users = ["niu","kaufmann","jarvis","alice","bob","worker"]
for _ in range(1000):
    print(random.choice(forms)(random.choice(users)))
PY

# After redact: lines should never contain "/Users/<lowercased-name>" or "/home/<lowercased-name>"
# (i.e. self-user gets ~/, other-user gets <name>:~/, /tmp /private/var stay literal)
self_user=$(whoami)
leak_count=0
while IFS= read -r line; do
  out=$(redact_cwd "$line")
  # A true leak is /Users/<name> or /home/<name> that is NOT preceded by ~ or > (i.e. not redacted).
  # ~/Users/... and <user>:~/Users/... are legitimate redacted forms — do not flag them.
  if echo "$out" | grep -qE '(^|[^~>])/Users/[a-z]|(^|[^~>])/home/[a-z]'; then
    leak_count=$((leak_count + 1))
  fi
done < "$tmp"

[ "$leak_count" -eq 0 ] || { echo "FAIL: $leak_count leaks found"; exit 1; }
echo "PASS test-property-cwd-redact-no-leak.sh (1000 paths)"
