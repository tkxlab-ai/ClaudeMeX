#!/usr/bin/env bash
# extract-sections.sh — H2 section extraction + normalization
# Sourced as a library. Strict-mode options are the caller's responsibility;
# we do not mutate the caller's shell here.

# extract_sections <md_file>
# Prints one line per section: <section_id>\t<tmpfile_with_body>
# section_id = "rules/<basename>::H2 title" (or "<basename>::H2 title" if not under rules/)
extract_sections() {
    local file="$1"
    local rel
    if [[ "$file" =~ /rules/ ]]; then
        rel="rules/$(basename "$file")"
    else
        rel="$(basename "$file")"
    fi

    # We use a shell loop rather than pure awk to keep macOS BWK awk compatible
    # (systime() is GNU awk only; mktemp is more portable for temp file creation).
    local title="" body="" tmp
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Match "##" followed by ANY run of whitespace (space, tab, multi).
        # Earlier code only stripped the literal "## " prefix, which produced
        # malformed section IDs for "##\tTitle" or "##  Title" inputs.
        if [[ "$line" =~ ^##[[:space:]]+ ]]; then
            if [[ -n "$title" ]]; then
                tmp=$(mktemp /tmp/sect.XXXXXX)
                printf '%s' "$body" > "$tmp"
                printf '%s::%s\t%s\n' "$rel" "$title" "$tmp"
            fi
            # Strip "##" + any leading whitespace generically
            title="${line#"##"}"
            title="${title#"${title%%[![:space:]]*}"}"
            # strip trailing whitespace from title
            title="${title%"${title##*[![:space:]]}"}"
            # Reject titles containing control characters (Codex A3).
            # Markdown is read by an LLM downstream; control chars in a
            # heading are an attack/corruption signal — drop the section.
            case "$title" in
                *[$'\001'-$'\037'$'\177']*)
                    echo "extract_sections: rejecting section with control char in title (file=$rel)" >&2
                    title=""; body=""; continue
                    ;;
            esac
            body=""
        elif [[ -n "$title" ]]; then
            body="${body}${line}"$'\n'
        fi
    done < "$file"
    if [[ -n "$title" ]]; then
        tmp=$(mktemp /tmp/sect.XXXXXX)
        printf '%s' "$body" > "$tmp"
        printf '%s::%s\t%s\n' "$rel" "$title" "$tmp"
    fi
}

# normalize_body — reads stdin, writes stdout
# Rules: CRLF→LF, strip trailing whitespace per line, strip BOM at start,
#        collapse runs of ≥2 blank lines to 1, strip leading and trailing
#        blank lines entirely (so the same section content hashes identically
#        whether it sits in the middle of a file or at EOF — see test 6
#        in test-merge-extract-sections.sh).
normalize_body() {
    sed -e 's/\r$//' \
        -e 's/[[:space:]]*$//' \
        | sed $'1s/^\xef\xbb\xbf//' \
        | awk '
          /^$/ { blank=1; next }
          { if (have_printed && blank) print ""; print; blank=0; have_printed=1 }
        '
}

# hash_body — reads stdin, prints sha256 hex (64 chars)
hash_body() {
    shasum -a 256 | awk '{print $1}'
}
