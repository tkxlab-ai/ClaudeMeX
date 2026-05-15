#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../scripts/lib/behavior-schema.sh"

# Path-traversal style cwd should pass through as literal (no actual filesystem read)
got=$(redact_cwd "../../etc/passwd")
[ "$got" = "../../etc/passwd" ] || { echo "FAIL traversal: $got"; exit 1; }

# Even a /Users/niu/-prefixed traversal stays literal — no shell expansion
got=$(redact_cwd "/Users/niu/../../etc/passwd")
echo "$got" | grep -qE 'etc/passwd' || { echo "FAIL: lost suffix: $got"; exit 1; }
# But /Users/niu/ part should redact
echo "$got" | grep -q '^~' || { echo "FAIL: prefix not redacted: $got"; exit 1; }
echo "PASS test-adv-cwd-traversal.sh"
