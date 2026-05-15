#!/usr/bin/env bash
# vote-sections.sh — majority-vote algorithm for cross-machine merge
# Sourced as a library. Strict-mode options are the caller's responsibility;
# we do not mutate the caller's shell here.

# compute_K <N>
# K = max(2, ceil(N/2))
compute_K() {
    local n="$1"
    local half=$(( (n + 1) / 2 ))   # ceil(N/2) for non-negative N
    if [ "$half" -lt 2 ]; then
        echo 2
    else
        echo "$half"
    fi
}

# vote_section_hashes <K> <hash1> <hash2> ...
# Stdout: the majority hash if any group's count >= K
# Exit:   0 on consensus; 1 on no-consensus (empty stdout)
vote_section_hashes() {
    local k="$1"; shift
    [ "$#" -eq 0 ] && return 1
    local winner_count winner_hash
    read -r winner_count winner_hash < <(printf '%s\n' "$@" | sort | uniq -c | sort -rn | head -1)
    if [ -z "$winner_count" ] || [ "$winner_count" -lt "$k" ]; then
        return 1
    fi
    echo "$winner_hash"
    return 0
}
