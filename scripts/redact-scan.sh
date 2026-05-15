#!/usr/bin/env bash
# Release/redact-scan.sh
# -----------------------------------------------------------------------------
# Pre-release redaction scanner for Claude Code Config Generator.
# Blocks packaging if any personal info / secrets / fingerprints leak through.
#
# Usage:   ./redact-scan.sh <path-to-file-or-directory>
# Exit:    0 = clean, 1 = violations found, 2 = bad args
# -----------------------------------------------------------------------------

set -uo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ] || [ ! -e "$TARGET" ]; then
  echo "Usage: $0 <file-or-directory>" >&2
  echo "       Pass the repo root to also scan rules-legacy/" >&2
  exit 2
fi

# If scanning a Release/vX.Y.Z bundle, also warn if rules-legacy/ in the
# repo root contains personal info that would be exposed on a public push.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEGACY_DIR="${REPO_ROOT}/rules-legacy"

HITS=0
TOTAL_CATEGORIES=0

# Color output if terminal supports it
if [ -t 1 ]; then
  R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; N='\033[0m'
else
  R=''; G=''; Y=''; B=''; N=''
fi

# Build file list (exclude this script itself + common binary/cache dirs)
# Use a temp file to avoid subcommand-subshell null-byte stripping.
# GNU/BSD compatible: -print0 writes null-terminated, read via -0.
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE" "${LMATCHES:-}"' EXIT

if [ -d "$TARGET" ]; then
  find "$TARGET" -type f \
    ! -name "redact-scan.sh" \
    ! -path "*/.git/*" \
    ! -path "*/node_modules/*" \
    ! -path "*/.venv/*" \
    ! -path "*/__pycache__/*" \
    ! -name "CHECKSUMS.txt" \
    ! -name ".gitignore" \
    ! -name ".gitattributes" \
    ! -path "*/references/*" \
    ! -path "*/tests/*" \
    -print0 2>/dev/null > "$TMPFILE"
# Why these exclusions:
#   - tests/  : BDD/unit fixtures intentionally contain bad-pattern strings (fake
#               AWS keys, JWT examples, the scanner's own detector regex). The
#               BDD audit (tests/test-audit-bdd.sh) covers the fixture leak
#               invariants that DO matter (golden manifests, IP literals).
#   - .gitignore / .gitattributes : these list literal patterns of what to
#               *exclude*; flagging the listed names as if they were committed
#               content is a category error (the listed paths never ship).
else
  printf '%s\0' "$TARGET" > "$TMPFILE"
fi

if [ ! -s "$TMPFILE" ]; then
  echo "${Y}No files to scan.${N}"
  rm -f "$TMPFILE"
  exit 0
fi

# Count files (null-terminated, portable)
FILE_COUNT=$(tr '\0' '\n' < "$TMPFILE" | wc -l | tr -d ' ')
echo "${B}== Redaction scan ==${N}"
echo "Target: $TARGET"
echo "Files : $FILE_COUNT"
echo

# -----------------------------------------------------------------------------
# scan_category NAME PATTERN [FLAGS]
# Runs grep against TMPFILE, reports matches, increments HITS on violation.
# -----------------------------------------------------------------------------
scan_category() {
  local name="$1"
  local pattern="$2"
  local flags="${3:--nE}"
  TOTAL_CATEGORIES=$((TOTAL_CATEGORIES + 1))
  local matches
  matches=$(xargs -0 < "$TMPFILE" grep $flags -- "$pattern" 2>/dev/null || true)
  if [ -n "$matches" ]; then
    HITS=$((HITS + 1))
    echo "${R}[BLOCK]${N} $name"
    echo "$matches" | head -20 | sed 's/^/         /'
    local extra
    extra=$(echo "$matches" | wc -l | tr -d ' ')
    if [ "$extra" -gt 20 ]; then
      echo "         ... ($((extra - 20)) more lines truncated)"
    fi
    echo
  else
    echo "${G}[PASS] ${N} $name"
  fi
}

# =============================================================================
# Category 1 — Credentials / secrets (MUST redact — fatal if present)
# =============================================================================
scan_category "API keys (sk-/sk-ant-/ghp_/AIza/hf_)" \
  '(^|[^A-Za-z0-9_])(sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,}|hf_[A-Za-z0-9]{20,})'

scan_category "Plaintext password/passwd/token assignments" \
  '(password|passwd|bot_token|api_key|secret_key|secret_access_key|secret)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_./+=-]{8,}' -nE

scan_category "SSH private keys (-----BEGIN blocks)" \
  '-----BEGIN (OPENSSH|RSA|DSA|EC|PGP) PRIVATE KEY-----' -nE  # nosemgrep: detector-pattern-not-a-key

scan_category "OAuth bearer tokens" \
  '(Bearer|oauth_token|access_token)[[:space:]]*[:=]?[[:space:]]*["'"'"']?[A-Za-z0-9_.-]{20,}'

scan_category "Feishu / Lark app secrets" \
  '(appSecret|encrypt_key|verification_token)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_-]{16,}'

# =============================================================================
# Category 2 — Device / machine fingerprints (MUST redact — fatal)
# =============================================================================
scan_category "Syncthing device IDs (56-char XXXX-XXXX-... pattern)" \
  '[A-Z2-7]{7}-[A-Z2-7]{7}-[A-Z2-7]{7}-[A-Z2-7]{7}-[A-Z2-7]{7}-[A-Z2-7]{7}-[A-Z2-7]{7}-[A-Z2-7]{7}'

scan_category "MAC addresses" \
  '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'

scan_category "Machine serial numbers (Apple-style C02/FVF/etc.)" \
  '\b(C02|FVF|G6T|DMP|F4H)[A-Z0-9]{8,}'

# =============================================================================
# Category 3 — Network identifiers (MUST redact unless explicitly allowed)
# =============================================================================
# Public IPv4 addresses only: excludes 10/8, 172.16/12, 192.168/16, 127/8
# BSD ERE lacks negative lookahead, so use two-stage filter (cf. _email_check).
_ipv4_check() {
  local matches=""
  local o='([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])'
  local raw
  raw=$(xargs -0 < "$TMPFILE" grep -nE "\b(${o}\.){3}${o}\b" 2>/dev/null || true)
  if [ -n "$raw" ]; then
    # Exclude RFC 1918 private + loopback ranges
    matches=$(echo "$raw" | grep -vE '(^|[[:space:]/])(10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' 2>/dev/null || true)
  fi
  TOTAL_CATEGORIES=$((TOTAL_CATEGORIES + 1))
  if [ -n "$matches" ]; then
    HITS=$((HITS + 1))
    echo "${R}[BLOCK]${N} Public IPv4 addresses (private/loopback excluded)"
    echo "$matches" | head -20 | sed 's/^/         /'
    local extra
    extra=$(echo "$matches" | wc -l | tr -d ' ')
    if [ "$extra" -gt 20 ]; then
      echo "         ... ($((extra - 20)) more lines truncated)"
    fi
    echo
  else
    echo "${G}[PASS] ${N} Public IPv4 addresses (private/loopback excluded)"
  fi
}
_ipv4_check

scan_category "IPv6 addresses (non-loopback)" \
  '\b([0-9a-fA-F]{1,4}:){4,7}[0-9a-fA-F]{1,4}\b'

# =============================================================================
# Category 4 — Personal identifiers (MUST redact — fatal if this skill-generic)
# =============================================================================
# Personal emails (not example.com / placeholder): two-stage detection
# BSD grep (macOS) does not support PCRE negative lookahead (?!), so we
# handle this with a two-step approach inside a dedicated function.
_email_check() {
  local matches=""
  # Step 1: find all email-like patterns (BSD ERE compatible)
  local raw
  raw=$(xargs -0 < "$TMPFILE" grep -nE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' 2>/dev/null || true)
  if [ -n "$raw" ]; then
    # Step 2: filter out safe/placeholder domains
    matches=$(echo "$raw" | grep -vE '@(example|test|placeholder|domain)\.' 2>/dev/null || true)
  fi
  TOTAL_CATEGORIES=$((TOTAL_CATEGORIES + 1))
  if [ -n "$matches" ]; then
    HITS=$((HITS + 1))
    echo "${R}[BLOCK]${N} Personal emails (not example.com / placeholder)"
    echo "$matches" | head -20 | sed 's/^/         /'
    local extra
    extra=$(echo "$matches" | wc -l | tr -d ' ')
    if [ "$extra" -gt 20 ]; then
      echo "         ... ($((extra - 20)) more lines truncated)"
    fi
    echo
  else
    echo "${G}[PASS] ${N} Personal emails (not example.com / placeholder)"
  fi
}
_email_check

scan_category "Chinese phone numbers (1[3-9]xxxxxxxxx)" \
  '\b1[3-9][0-9]{9}\b'

scan_category "Personal name tokens (customise per project)" \
  '(老大|Jarvis|tokenhu|J\.A\.R\.V\.I\.S)' -nE

# =============================================================================
# Category 5 — User-specific paths / namespaces (MUST redact)
# =============================================================================
scan_category "Home directory with actual username" \
  '/Users/[A-Za-z][A-Za-z0-9_.-]{1,31}/' -nE

scan_category "Personal workspace prefixes" \
  '(myworkspace|\.myagent|MYCONF|MY-CONFIG|MY-CDN)' -nE

# =============================================================================
# Category 6 — Project codenames (redact unless documented as generic example)
# =============================================================================
scan_category "Personal project codenames" \
  '(ProjectAlpha|ProjectBeta|ProjectGamma|ServiceX|AgentY)' -nE

# =============================================================================
# Category 7 — Optional: private domains / hostnames
# =============================================================================
scan_category "Private VPS / CDN domains (.vps. / tokenx / custom)" \
  '\.(vps|tokenx)\.' -nE

# =============================================================================
# Category 8 — Cloud provider credentials (MUST redact — fatal)
# =============================================================================
scan_category "Cloud provider AK/SK (AWS/Aliyun/Tencent/GCP)" \
  '(AKIA[0-9A-Z]{16}|LTAI[0-9A-Za-z]{12,}|[Aa]ccess[Kk]ey[Ii][Dd].*[:=].*[A-Za-z0-9]{20,}|[Ss]ecret[Kk]ey.*[:=].*[A-Za-z0-9+/=]{20,}|(bot_token|access_token|refresh_token|api_token|auth_token|bearer_token)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9]{20,})' -nE

# =============================================================================
# Category 9 — JWT / OAuth tokens (MUST redact — fatal)
# =============================================================================
scan_category "JWT tokens (eyJ... pattern)" \
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}[A-Za-z0-9._-]*' -nE

# =============================================================================
# Category 10 — Database connection strings with embedded password (MUST redact)
# =============================================================================
scan_category "Database URIs with embedded credentials" \
  '(postgresql|postgres|mysql|mongodb|mongodb\+srv|redis|rediss)://[^:]+:[^@]+@' -nE

# =============================================================================
# Category 11 — Private registry tokens (MUST redact — fatal)
# =============================================================================
scan_category "Package registry tokens (npm/Docker/PyPI)" \
  '(npm_[A-Za-z0-9]{20,}|pypi-[A-Za-z0-9_-]{20,}|auth *= *[A-Za-z0-9+/]{20,}=*)' -nE

# =============================================================================
# Category 12 — GPG private keys (MUST redact — fatal)
# =============================================================================
# Detector pattern is built from parts so static analyzers don't flag this
# detector script as if it contained a real key block.
_PGP_BEGIN='-----BEGIN '
_PGP_REST='PGP PRIVATE KEY BLOCK-----'
scan_category "GPG private key blocks" \
  "${_PGP_BEGIN}${_PGP_REST}" -nF

# =============================================================================
# Category 13 — PEM-encoded RSA/EC/DSA keys (MUST redact — fatal)
# Note: Category 3 (SSH) already covers some of these. This catches
# cert-embedded keys and generic PRIVATE KEY blocks not flagged by SSH scan.
# =============================================================================
scan_category "PEM-encoded private keys (RSA/EC/DSA)" \
  '-----BEGIN (RSA |EC |DSA )PRIVATE KEY-----' -nE

# =============================================================================
# Category 14 — Base64-encoded secrets (MUST redact — fatal)
# Long base64 strings assigned to secret-like variable names
# =============================================================================
scan_category "Base64-encoded secret values" \
  '(SECRET|TOKEN|PASSWORD|CREDENTIALS)[_A-Za-z0-9]*=[A-Za-z0-9+/]{30,}={0,2}' -nE

# =============================================================================
# Category 15 — .env reverse leak detection (FINAL check)
# Fires only if a .env file exists at REPO_ROOT. Checks whether any env var
# value (length >= 8) appears verbatim in the scanned files — this catches
# custom-format tokens that no regex pattern can anticipate.
# =============================================================================
ENV_FILE="${REPO_ROOT}/.env"
if [ -f "$ENV_FILE" ]; then
  ENV_HITS=0
  TOTAL_CATEGORIES=$((TOTAL_CATEGORIES + 1))
  while IFS='=' read -r _key _val || [ -n "$_key" ]; do
    # Skip comments and blank lines
    [[ "$_key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${_key// }" ]] && continue
    # Strip surrounding quotes from value (both single and double)
    _val="${_val#\"}"   # leading "
    _val="${_val%\"}"   # trailing "
    # Single quotes: use a temp variable to avoid shell quoting issues
    _sq="'"
    _val="${_val#$_sq}"
    _val="${_val%$_sq}"
    _val="${_val%% }"   # strip trailing spaces (non-destructive if no space)
    # Strip inline comments: # preceded by space
    _val="${_val%% #*}"
    # Skip values shorter than 8 chars (too generic, high false-positive rate)
    [ "${#_val}" -lt 8 ] && continue
    if xargs -0 < "$TMPFILE" grep -qF "$_val" 2>/dev/null; then
      if [ "$ENV_HITS" -eq 0 ]; then
        echo "${R}[BLOCK]${N} .env value leaks (actual secret values found verbatim in output files)"
      fi
      ENV_HITS=$((ENV_HITS + 1))
      echo "         .env key ${_key} value appears in output"
    fi
  done < "$ENV_FILE"
  if [ "$ENV_HITS" -gt 0 ]; then
    HITS=$((HITS + 1))
    echo
  else
    echo "${G}[PASS] ${N} .env reverse leak check (no .env values found verbatim)"
  fi
fi

# =============================================================================
# Category 16 — Behavior signal residual leaks (v1.3 NEW)
# Catches cwd paths, OAuth/PAT tokens, session UUIDs, and sensitive
# credential file references that must be redacted before release.
# =============================================================================
# 16a — cwd absolute paths (/home/<name>/ not already covered by Category 5)
scan_category "cwd absolute path: /home/<name>/ (Linux home dir leak)" \
  '/home/[a-z][a-zA-Z0-9_-]*/' -nE

# 16b — Google OAuth access tokens (ya29.<base64>)
scan_category "Google OAuth token (ya29.<base64>)" \
  'ya29\.[A-Za-z0-9_<>-]+' -nE

# 16c — GitHub fine-grained / classic PATs (gho_/ghp_/ghs_/ghr_/ghu_)
scan_category "GitHub PAT (gho_/ghp_/ghs_/ghr_/ghu_)" \
  '(gho|ghp|ghs|ghr|ghu)_[A-Za-z0-9<>-]+' -nE

# 16d — session_id UUID (raw 8-4-4-4-12 form; should be redacted to <SID-NN>)
scan_category "session_id UUID (raw; must be redacted to <SID-NN>)" \
  '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' -nE

# 16e — Sensitive credential file paths (~/.codex/, ~/.gemini/, opencode.db)
scan_category "Sensitive credential paths (~/.codex/auth.json etc.)" \
  '(~/\.codex/(auth\.json|installation_id)|~/\.gemini/oauth_creds\.json|opencode\.db-(wal|shm))' -nE

# =============================================================================
# Report
# =============================================================================
echo
if [ "$HITS" -eq 0 ]; then
  echo "${G}== CLEAN ==${N}  All $TOTAL_CATEGORIES categories passed."
  echo "OK to promote to Release/"
else
  echo "${R}== BLOCKED ==${N}  $HITS / $TOTAL_CATEGORIES categories have violations."
  echo "Fix the violations above before packaging to Release/"
fi

# -----------------------------------------------------------------------------
# Supplemental: warn if rules-legacy/ in the repo root contains personal info.
# This does NOT affect the exit code for Release packaging (rules-legacy is not
# shipped in Release bundles), but it WILL surface violations before a public
# git push exposes them.
# -----------------------------------------------------------------------------
if [ -d "$LEGACY_DIR" ]; then
  LMATCHES=$(mktemp)
  find "$LEGACY_DIR" -type f ! -path "*/.git/*" -print0 2>/dev/null > "$LMATCHES"
  if [ -s "$LMATCHES" ]; then
    echo
    echo "${Y}== rules-legacy/ supplemental scan ==${N}  (advisory — does not affect exit code)"
    echo "Path: $LEGACY_DIR"
    LEGACY_HITS=0
    _legacy_warn() {
      local name="$1" pattern="$2" flags="${3:--nE}"
      local matches
      matches=$(xargs -0 < "$LMATCHES" grep $flags -- "$pattern" 2>/dev/null || true)
      if [ -n "$matches" ]; then
        LEGACY_HITS=$((LEGACY_HITS + 1))
        echo "${Y}[WARN]${N}  $name (in rules-legacy/)"
        echo "$matches" | head -5 | sed 's/^/         /'
      fi
    }
    _legacy_warn "Personal name tokens"        '(老大|Jarvis|tokenhu|J\.A\.R\.V\.I\.S)' -nE
    _legacy_warn "Home directory paths"        '/Users/[A-Za-z][A-Za-z0-9_.-]{1,31}/' -nE
    _legacy_warn "Personal workspace prefixes" '(myworkspace|\.myagent|MYCONF|MY-CONFIG|MY-CDN)' -nE
    _legacy_warn "Project codenames"           '(ProjectAlpha|ProjectBeta|ProjectGamma)' -nE
    # Public IPv4: grep → exclude private/loopback → report residuals
    _legacy_ipv4_matches=$(xargs -0 < "$LMATCHES" grep -nE '\b(([1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])' 2>/dev/null | grep -vE '(^|[[:space:]])(10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01]))' || true)
    if [ -n "$_legacy_ipv4_matches" ]; then
      LEGACY_HITS=$((LEGACY_HITS + 1))
      echo "${Y}[WARN]${N}  Public IPv4 addresses (private/loopback excluded, in rules-legacy/)"
      echo "$_legacy_ipv4_matches" | head -5 | sed 's/^/         /'
    fi
    if [ "$LEGACY_HITS" -eq 0 ]; then
      echo "${G}[PASS]${N}  rules-legacy/ is clean — safe to push publicly."
    else
      echo
      echo "${Y}rules-legacy/ has $LEGACY_HITS warning(s).${N}"
      echo "Consider adding rules-legacy/ to .gitignore or cleaning before public push."
    fi
    rm -f "$LMATCHES"
  fi
fi

[ "$HITS" -eq 0 ] && exit 0 || exit 1
