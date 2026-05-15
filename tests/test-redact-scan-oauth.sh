#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
# Defanged placeholders (angle brackets break pattern matching for real creds)
cat > "$fixture/tokens.md" <<'MD'
Google OAuth: ya29.<TOKEN-SHAPE-PLACEHOLDER-DO-NOT-FLAG>
GitHub PAT: gho_<PLACEHOLDER-AAAAA>
MD
out=$(bash "$proj/scripts/redact-scan.sh" "$fixture" 2>&1 || true)
echo "$out" | grep -qE '\[BLOCK\].*(Google OAuth|GitHub PAT|ya29|gho_)' \
  || { echo "FAIL OAuth: expected BLOCK for ya29 and gho_ patterns. Output: $out"; exit 1; }
echo "PASS test-redact-scan-oauth.sh"
