#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/refs.md" <<'MD'
See ~/.codex/auth.json and ~/.gemini/oauth_creds.json plus ~/.codex/installation_id
MD
out=$(bash "$proj/scripts/redact-scan.sh" "$fixture" 2>&1 || true)
echo "$out" | grep -qE '\[BLOCK\].*(Sensitive credential|auth\.json|oauth_creds|installation_id)' \
  || { echo "FAIL sensitive-paths: expected BLOCK for credential paths. Output: $out"; exit 1; }
echo "PASS test-redact-scan-sensitive-paths.sh"
