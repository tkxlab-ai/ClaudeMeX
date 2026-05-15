#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../scripts/lib/behavior-schema.sh"

# Case 1: /Users/<self>/foo → ~/foo
self=$(whoami)
got=$(redact_cwd "/Users/$self/coding/foo")
[ "$got" = "~/coding/foo" ] || { echo "FAIL case1: $got"; exit 1; }
echo "PASS case1"

# Case 2: /Users/<other>/foo → <other>:~/foo
got=$(redact_cwd "/Users/kaufmann/coding/foo")
[ "$got" = "<kaufmann>:~/coding/foo" ] || { echo "FAIL case2: $got"; exit 1; }

# Case 3: Linux /home/<self>/ → ~/
self=$(whoami)
got=$(redact_cwd "/home/$self/coding/foo")
[ "$got" = "~/coding/foo" ] || { echo "FAIL case3: $got"; exit 1; }

# Case 4: nested same-name path stays accurate
got=$(redact_cwd "/Users/$self/Users/foo")
[ "$got" = "~/Users/foo" ] || { echo "FAIL case4: $got"; exit 1; }

# Case 5: empty / lone slash boundary
got=$(redact_cwd "/"); [ "$got" = "/" ] || { echo "FAIL case5a: $got"; exit 1; }
got=$(redact_cwd "");  [ "$got" = "" ]  || { echo "FAIL case5b: '$got'"; exit 1; }

# Case 6: bare other-user path (no trailing slash) — must collapse
got=$(redact_cwd "/Users/alice")
[ "$got" = "<alice>:~" ] || { echo "FAIL case6 (bare other-user macOS): $got"; exit 1; }

# Case 7: bare /home/<other> (Linux) — must collapse
got=$(redact_cwd "/home/bob")
[ "$got" = "<bob>:~" ] || { echo "FAIL case7 (bare other-user Linux): $got"; exit 1; }

echo "PASS test-cwd-redactor.sh all 7 cases"
