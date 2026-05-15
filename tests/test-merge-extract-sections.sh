#!/usr/bin/env bash
set -uo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SELF_DIR/.." && pwd)"
LIB="$PROJECT_ROOT/scripts/lib/extract-sections.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

. "$LIB"

TMP=$(mktemp -d); trap "rm -rf '$TMP'" EXIT
mkdir -p "$TMP/rules"

# Fixture: rules/02-execution.md with two H2 sections
cat > "$TMP/rules/02-execution.md" <<EOF
# 02 — Execution

Intro text outside any section.

## Linus 三问

Question one.
Question two.

## 1by1 协议

Step one.
Step two.
EOF

# Test 1: extract counts sections
mapfile -t out < <(extract_sections "$TMP/rules/02-execution.md")
[ "${#out[@]}" -eq 2 ] && pass "extracts 2 sections" || fail "got ${#out[@]} sections"

# Test 2: section_id format
echo "${out[0]}" | grep -qF "rules/02-execution.md::Linus 三问" && pass "section_id correct" \
    || fail "got: ${out[0]}"

# Test 3: normalize collapses CRLF and trailing whitespace
# xxd wraps at 16 bytes; concatenate all hex bytes (stripping offsets and ASCII column)
# to find the full sequence "line1\nline2\n\nline3" = 6c696e65310a6c696e65320a0a6c696e6533
printf "line1   \r\nline2\r\n\r\n\r\nline3\r\n" > "$TMP/raw.txt"
norm=$(normalize_body < "$TMP/raw.txt" | xxd | awk '{for(i=2;i<=9;i++) printf $i}')
echo "$norm" | grep -qE "6c696e65310a6c696e65320a0a6c696e6533" && pass "normalize CRLF+ws+blanks" \
    || fail "normalize got: $norm"

# Test 4: hash_body is deterministic
h1=$(printf "abc\n" | hash_body)
h2=$(printf "abc\n" | hash_body)
[ "$h1" = "$h2" ] && [ ${#h1} -eq 64 ] && pass "hash_body deterministic sha256" \
    || fail "hash mismatch h1='$h1' h2='$h2'"

# Test 5: normalize_body strips UTF-8 BOM at start
printf '\xef\xbb\xbfhello\n' > "$TMP/bom.txt"
norm=$(normalize_body < "$TMP/bom.txt")
[ "$norm" = "hello" ] && pass "normalize strips BOM" || fail "BOM not stripped, got: $(printf '%s' "$norm" | xxd | head -1)"

# Test 6: SAME-CONTENT section produces SAME hash regardless of trailing-section
# context (regression: dogfood revealed last-section vs middle-section produced
# different bodies because trailing blank lines from the next "## " were
# included in non-last cases but not in last cases).
cat > "$TMP/rules/last-section.md" <<EOF
## Shared Section

shared body line 1

shared body line 2
EOF

cat > "$TMP/rules/middle-section.md" <<EOF
## Shared Section

shared body line 1

shared body line 2

## Trailing Section

irrelevant
EOF

mapfile -t las < <(extract_sections "$TMP/rules/last-section.md")
mapfile -t mid < <(extract_sections "$TMP/rules/middle-section.md")
las_body=$(echo "${las[0]}" | cut -f2)
mid_body=$(echo "${mid[0]}" | cut -f2)
las_hash=$(normalize_body < "$las_body" | hash_body)
mid_hash=$(normalize_body < "$mid_body" | hash_body)
[ "$las_hash" = "$mid_hash" ] && pass "same content → same hash regardless of position" \
    || fail "hash differs between last vs middle section: las=$las_hash mid=$mid_hash"

# Test 7: H2 with multi-space / tab whitespace after "##" must produce a
# clean section title (Codex review M2). Original code only stripped "## "
# (single space), so "##\tTitle" or "##  Title" yielded malformed IDs.
cat > "$TMP/rules/whitespace.md" <<'EOF'
## Tab-prefixed title
body for tab.

##   Multi-space title
body for multi-space.
EOF
# Replace the tab marker after creating the file (heredoc would normalize)
sed -i '' '1s/.*/##	Tab-prefixed title/' "$TMP/rules/whitespace.md" 2>/dev/null \
    || sed -i '1s/.*/##	Tab-prefixed title/' "$TMP/rules/whitespace.md"

mapfile -t ws < <(extract_sections "$TMP/rules/whitespace.md")
# Expect 2 sections, neither containing leading whitespace in the title
echo "${ws[0]}" | grep -qF "::Tab-prefixed title" && pass "## + tab → clean title" \
    || fail "tab title malformed: ${ws[0]}"
echo "${ws[1]}" | grep -qF "::Multi-space title" && pass "## + multi-space → clean title" \
    || fail "multi-space title malformed: ${ws[1]}"

# Test 9 (Codex A3): section title with control characters → reject section.
# Stage a file with a title containing literal \x07 (BEL). extract_sections
# should skip the section and emit a warning.
{
    printf '## Good title\n\nclean body.\n\n'
    printf '## Bad\x07title\n\nbody after bad title.\n'
} > "$TMP/rules/badtitle.md"
mapfile -t bt < <(extract_sections "$TMP/rules/badtitle.md" 2>/dev/null)
# Expect exactly 1 section (the good one). The bad-title section must be dropped.
[ "${#bt[@]}" -eq 1 ] && pass "A3: section with control-char title → dropped (1 section emitted)" \
    || fail "A3: control char in title not rejected (${#bt[@]} sections)"
echo "${bt[0]}" | grep -qF "::Good title" && pass "A3: good title still extracted" \
    || fail "A3: good title not preserved: ${bt[0]}"

echo "==="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
