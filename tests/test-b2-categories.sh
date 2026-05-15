#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# TDD test for B2: 7 missing redact categories
# -----------------------------------------------------------------------------
set -e
PASS=0
FAIL=0
SKIPPED=0
TESTS_RUN=0

pass() { PASS=$((PASS + 1)); TESTS_RUN=$((TESTS_RUN + 1)); echo "✅ PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TESTS_RUN=$((TESTS_RUN + 1)); echo "❌ FAIL: $1"; }

echo "=== TDD-B2: 7 Missing Redact Categories Tests ==="
echo

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

test_detect() {
  local label="$1" input="$2"
  local testfile="${TMPD}/test-${label}.md"
  echo "$input" > "$testfile"
  EXIT_CODE=0
  bash Release/redact-scan.sh "$testfile" > "${TMPD}/out-${label}.txt" 2>&1 || EXIT_CODE=$?
  if grep -q '\[BLOCK\]' "${TMPD}/out-${label}.txt" 2>/dev/null; then
    pass "$label detected"
  else
    fail "$label NOT detected"
    echo "         Input: $(echo "$input" | head -c 80)"
  fi
  rm -f "$testfile" "${TMPD}/out-${label}.txt"
}

# =============================================================================
# Cat 8-1: Cloud AK/SK (AWS, Aliyun, Tencent, GCP)
# =============================================================================
echo "--- Cloud AK/SK ---"
test_detect "aws-ak" "aws_access_key_id = AKIAIOSFODNN7EXAMPLE"
test_detect "aws-sk" "aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
test_detect "aliyun-ak" "accessKeyId: LTAI5tB2mD41nzvQ5EjH2XzY"
test_detect "tencent-sk" "TENCENT_SECRET_KEY=aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"

# =============================================================================
# Cat 8-2: GPG private key blocks
# =============================================================================
echo "--- GPG keys ---"
test_detect "gpg-key" "-----BEGIN PGP PRIVATE KEY BLOCK-----"

# =============================================================================
# Cat 8-3: Base64 encoded secrets (>=20 chars, common patterns)
# =============================================================================
echo "--- Base64 secrets ---"
test_detect "base64-secret" "SECRET_BASE64=dGhpcyBpcyBhIHNlY3JldCB0aGF0IGlzIGJhc2U2NCBlbmNvZGVk"

# =============================================================================
# Cat 8-4: JWT tokens (header.payload.signature pattern)
# =============================================================================
echo "--- JWT tokens ---"
test_detect "jwt-token" "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NQ"

# =============================================================================
# Cat 8-5: Database connection strings with password
# =============================================================================
echo "--- DB connection strings ---"
test_detect "postgres-uri" "DATABASE_URL=postgresql://admin:MyP@ssw0rd!@db.example.com:5432/mydb"
test_detect "mysql-uri" "mysql://root:S3cretP@ss@localhost:3306/production"
test_detect "mongodb-uri" "mongodb+srv://user:hunter2@cluster0.abc.mongodb.net/admin"

# =============================================================================
# Cat 8-6: Private registry tokens (npm, Docker, PyPI)
# =============================================================================
echo "--- Registry tokens ---"
test_detect "npm-token" "//registry.npmjs.org/:_authToken=npm_abcDEFghiJKLmnoPQRstu"
test_detect "docker-cfg" "auth = ZG9ja2VyOnN1cGVyc2VjcmV0cGFzc3dvcmQxMjM="
test_detect "pypi-token" "pypi-AgEIcHlwaS5vcmcBMTIzND"

# =============================================================================
# Cat 8-7: Certificate/Key files
# =============================================================================
echo "--- Cert private keys ---"
test_detect "rsa-key" "-----BEGIN RSA PRIVATE KEY-----"
test_detect "ec-key" "-----BEGIN EC PRIVATE KEY-----"

# Cleanup
rm -rf "$TMPD"

echo
echo "=== Results: $PASS passed, $FAIL failed, $SKIPPED skipped ($TESTS_RUN tests) ==="
echo
if [ "$FAIL" -gt 0 ]; then
  echo "🔴 RED gate active — TDD cycle not complete. Fix required."
  exit 1
else
  echo "🟢 All tests green."
  exit 0
fi
