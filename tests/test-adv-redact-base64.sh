#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# Assemble a synthetic JWT-shaped token at runtime so the source file
# itself does not contain a literal token (avoiding scanner self-trigger).
# Format: eyJ<header_b64>.<eyJ<payload_b64>.<sig_b64>
# All segments are real base64url — the scanner's Category 9 pattern
# matches on the eyJ prefix + min-length segments, not on validity.
HDR="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
PAY="eyJzdWIiOiJ0ZXN0dXNlciIsImlhdCI6MTUxNjIzOTAyMn0"
SIG="SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
printf 'Token: %s.%s.%s\n' "$HDR" "$PAY" "$SIG" > "$fixture/jwt.md"

out=$(bash "$proj/scripts/redact-scan.sh" "$fixture" 2>&1 || true)
echo "$out" | grep -qE '(JWT|jwt|eyJ)' || { echo "FAIL JWT not caught: $out"; exit 1; }
echo "PASS test-adv-redact-base64.sh"
