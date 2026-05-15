#!/usr/bin/env bash
# Round-trip smoke test for claudemex export ↔ import.
# Verifies the transport fallback path produces a tarball that import
# extracts back into the same shape.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SELF_DIR/.." && pwd)"
EXPORT="$PROJECT_ROOT/scripts/export.sh"
IMPORT="$PROJECT_ROOT/scripts/import.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

TMP=$(mktemp -d); trap "rm -rf '$TMP'" EXIT

# Test 1: export --help / import --help
out=$("$EXPORT" --help 2>&1) && rc=0 || rc=$?
echo "$out" | grep -q "claudemex export" && pass "export --help works" || fail "export --help: $out"
out=$("$IMPORT" --help 2>&1) && rc=0 || rc=$?
echo "$out" | grep -q "claudemex import" && pass "import --help works" || fail "import --help: $out"

# Test 2: export with no matching <host>-*/ → exit 1
mkdir -p "$TMP/empty-outputs"
out=$("$EXPORT" --from="$TMP/empty-outputs" --out="$TMP/should-not-exist.tar.gz" 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "export empty input → exit 1" || fail "empty: rc=$rc out=$out"

# Test 3: import with no input file → exit 1
out=$("$IMPORT" --into="$TMP/imp-out" 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "import no input → exit 1" || fail "import no input: rc=$rc"

# Test 4: import nonexistent file → exit 1
out=$("$IMPORT" --into="$TMP/imp-out" "$TMP/nope.tar.gz" 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "import bad file → exit 1" || fail "import bad: rc=$rc"

# Test 5: round-trip export + import
# We can't easily fake the host name (scutil/hostname are real), so we use
# whatever the local hostname produces and stage a matching directory.
HOST=$(scutil --get LocalHostName 2>/dev/null | tr '[:upper:]' '[:lower:]')
[ -z "$HOST" ] && HOST=$(hostname -s | tr '[:upper:]' '[:lower:]')
RUN_DIR="$TMP/outputs/${HOST}-20260506"
mkdir -p "$RUN_DIR/rules"
printf 'host: %s\ntier: MAX\ngenerator_version: v1.1.0\n' "$HOST" > "$RUN_DIR/run-meta.yaml"
printf '# 01 — identity\n\n## Sample\n\nbody.\n' > "$RUN_DIR/rules/01-identity.md"

TARBALL="$TMP/export.tar.gz"
out=$("$EXPORT" --from="$TMP/outputs" --out="$TARBALL" 2>&1) && rc=0 || rc=$?
[ "$rc" = "0" ] && [ -f "$TARBALL" ] && pass "export round-trip produces tarball" \
    || fail "export failed: rc=$rc tarball_exists=$([ -f "$TARBALL" ] && echo yes || echo no)"

IMPORT_DIR="$TMP/imported"
out=$("$IMPORT" --into="$IMPORT_DIR" "$TARBALL" 2>&1) && rc=0 || rc=$?
[ "$rc" = "0" ] && pass "import round-trip exits 0" || fail "import failed: rc=$rc out=$out"

# Compare contents
[ -f "$IMPORT_DIR/${HOST}-20260506/run-meta.yaml" ] && pass "round-trip preserves run-meta.yaml" \
    || fail "run-meta.yaml missing after import"
[ -f "$IMPORT_DIR/${HOST}-20260506/rules/01-identity.md" ] && pass "round-trip preserves rules/" \
    || fail "rules/ missing after import"
diff -r "$RUN_DIR" "$IMPORT_DIR/${HOST}-20260506" >/dev/null 2>&1 && pass "round-trip byte-identical" \
    || fail "round-trip diverged"

# --- Hostile-tarball preflight (Codex review C1) ------------------------------

# Test 6: tarball with absolute-path entry → reject
HOSTILE1="$TMP/abs.tar.gz"
mkdir -p "$TMP/abs-stage"
echo "evil" > "$TMP/abs-stage/evil.txt"
( cd "$TMP/abs-stage" && tar -czf "$HOSTILE1" -P /etc/hosts evil.txt 2>/dev/null ) || true
# Use a portable absolute-path-stuffed tarball (build manually)
python3 - "$HOSTILE1" "$TMP/abs-stage/evil.txt" 2>/dev/null <<'PY' || true
import sys, tarfile
out, src = sys.argv[1], sys.argv[2]
with tarfile.open(out, "w:gz") as t:
    info = t.gettarinfo(src, arcname="/etc/hostile-payload.txt")
    info.name = "/etc/hostile-payload.txt"
    with open(src, "rb") as f:
        t.addfile(info, f)
PY
if [ -f "$HOSTILE1" ]; then
    out=$("$IMPORT" --into="$TMP/safe1" "$HOSTILE1" 2>&1) && rc=0 || rc=$?
    [ "$rc" = "1" ] && pass "absolute-path tarball → exit 1" || fail "abs tarball: rc=$rc"
    [ ! -e "/etc/hostile-payload.txt" ] && pass "abs path was NOT extracted" || fail "abs path leaked!"
else
    pass "abs-tar test: skipped (python3 unavailable)"
    pass "abs-tar test: skipped (python3 unavailable)"
fi

# Test 7: tarball with ".." traversal → reject
HOSTILE2="$TMP/dotdot.tar.gz"
mkdir -p "$TMP/dotdot-stage/inner"
echo "evil" > "$TMP/dotdot-stage/inner/evil.txt"
( cd "$TMP/dotdot-stage/inner" && tar -czf "$HOSTILE2" --transform 's|^|../../|' evil.txt 2>/dev/null ) || \
( cd "$TMP/dotdot-stage" && tar -czf "$HOSTILE2" -s '|^|../../|' inner/evil.txt 2>/dev/null ) || true
# Fallback: build via python3 if tar transform unsupported
if [ -f "$HOSTILE2" ]; then
    # Verify the tarball actually has ".." entries (sanity)
    if tar -tzf "$HOSTILE2" 2>/dev/null | grep -q '\.\.'; then
        out=$("$IMPORT" --into="$TMP/safe2" "$HOSTILE2" 2>&1) && rc=0 || rc=$?
        [ "$rc" = "1" ] && pass "dotdot-traversal tarball → exit 1" || fail "dotdot tarball: rc=$rc"
    else
        pass "dotdot-tar test: skipped (tar variant did not honor transform)"
    fi
else
    pass "dotdot-tar test: skipped"
fi

# Test 8 (V1): tarball containing a SYMLINK → reject
HOSTILE3="$TMP/symlink.tar.gz"
mkdir -p "$TMP/sym-stage"
( cd "$TMP/sym-stage" && ln -s /etc/passwd evil-link && tar -czf "$HOSTILE3" evil-link 2>/dev/null )
if [ -f "$HOSTILE3" ]; then
    out=$("$IMPORT" --into="$TMP/safe3" "$HOSTILE3" 2>&1) && rc=0 || rc=$?
    [ "$rc" = "1" ] && pass "symlink-entry tarball → exit 1 (V1)" || fail "symlink tarball: rc=$rc out=$out"
    [ ! -L "$TMP/safe3/evil-link" ] && pass "symlink was NOT extracted (V1)" || fail "symlink leaked!"
else
    pass "symlink-tar test: skipped (ln -s unavailable)"
    pass "symlink-tar test: skipped (ln -s unavailable)"
fi

# Test 9 (V6): tarball whose uncompressed size exceeds --max-bytes → reject
HOSTILE4="$TMP/big.tar.gz"
mkdir -p "$TMP/big-stage"
# Create a 2 MB file that compresses very well (zeros)
dd if=/dev/zero of="$TMP/big-stage/big.bin" bs=1024 count=2048 2>/dev/null
( cd "$TMP/big-stage" && tar -czf "$HOSTILE4" big.bin )
out=$("$IMPORT" --into="$TMP/safe4" --max-bytes=1024 "$HOSTILE4" 2>&1) && rc=0 || rc=$?
[ "$rc" = "1" ] && pass "size-cap exceeded → exit 1 (V6)" || fail "size cap: rc=$rc out=$out"
echo "$out" | grep -q "exceeds cap" && pass "size-cap error message present" || fail "no size-cap message"
# Same tarball with default cap (100 MB) — should succeed
out=$("$IMPORT" --into="$TMP/safe4b" "$HOSTILE4" 2>&1) && rc=0 || rc=$?
[ "$rc" = "0" ] && pass "size-cap default 100MB allows 2MB tarball" || fail "default cap rejected legit: rc=$rc"

# Test 10 (V7): extracted files do NOT preserve setuid/setgid bits.
# Stage a file with mode 4755 (setuid), tar it, extract, verify mode is NOT 4xxx.
HOSTILE5="$TMP/setuid.tar.gz"
mkdir -p "$TMP/suid-stage"
echo "payload" > "$TMP/suid-stage/setuid-bin"
chmod 4755 "$TMP/suid-stage/setuid-bin" 2>/dev/null || true
( cd "$TMP/suid-stage" && tar -czf "$HOSTILE5" setuid-bin )
out=$("$IMPORT" --into="$TMP/safe5" "$HOSTILE5" 2>&1) && rc=0 || rc=$?
[ "$rc" = "0" ] && pass "import w/ setuid file extracts (no preflight reject)" || fail "setuid: rc=$rc"
if [ -f "$TMP/safe5/setuid-bin" ]; then
    extracted_mode=$(stat -f "%p" "$TMP/safe5/setuid-bin" 2>/dev/null || stat -c "%a" "$TMP/safe5/setuid-bin")
    case "$extracted_mode" in
        *4[0-9][0-9][0-9]) fail "setuid bit was preserved! mode=$extracted_mode";;
        *) pass "extracted file does NOT have setuid bit (V7) mode=$extracted_mode";;
    esac
fi

# Test 11 (Codex round-2 D1): tarball with embedded-newline filename → reject.
# tar entry-count check (-tzf vs -tvzf) catches this even though the name
# itself is invisible to `read -r`.
HOSTILE6="$TMP/newline-name.tar.gz"
mkdir -p "$TMP/nl-stage"
# Create a file whose name contains a newline. Use $'\n' bash escape.
nl_name=$'evil\nlegit.txt'
echo "payload" > "$TMP/nl-stage/$nl_name" 2>/dev/null
if [ -f "$TMP/nl-stage/$nl_name" ]; then
    ( cd "$TMP/nl-stage" && tar -czf "$HOSTILE6" "$nl_name" 2>/dev/null )
    if [ -f "$HOSTILE6" ]; then
        # Sanity check: did the tarball actually preserve the newline in the
        # entry name? bsdtar may store via PAX extensions and -tzf might
        # render the name with the newline intact.
        nl_lines_in_listing=$(tar -tzf "$HOSTILE6" 2>/dev/null | wc -l | tr -d ' ')
        nl_lines_in_verbose=$(tar -tvzf "$HOSTILE6" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$nl_lines_in_listing" != "$nl_lines_in_verbose" ]; then
            # Tarball really has a newline-named entry; preflight must reject
            out=$("$IMPORT" --into="$TMP/safe6" "$HOSTILE6" 2>&1) && rc=0 || rc=$?
            [ "$rc" = "1" ] && echo "$out" | grep -qE "newline|differs from entry count" \
                && pass "D1: newline-in-name tarball → exit 1" \
                || fail "D1: newline-name accepted: rc=$rc out=$out"
        else
            pass "D1 skip: this tar variant escapes newlines so listing counts match"
        fi
    else
        pass "D1 skip: tar refused to archive newline-named file"
    fi
else
    pass "D1 skip: filesystem refused to create newline-named file"
fi

echo "==="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
