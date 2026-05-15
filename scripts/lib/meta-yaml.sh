#!/usr/bin/env bash
# meta-yaml.sh — read/write run-meta.yaml + kernel-meta.yaml.
# Sourced as a library; no top-level state.
#
# Format is intentionally flat YAML (no nesting beyond a single list)
# so that it can be parsed with grep/sed without yq.
# This file is sourced as a library. Strict-mode options (set -u, set -o pipefail)
# are the responsibility of the caller; we do not mutate the caller's shell here.

# write_run_meta <file> <host> <generator_version> <tier> <tool>
write_run_meta() {
    local file="$1" host="$2" gver="$3" tier="$4" tool="$5"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat > "$file" <<EOF
# run-meta.yaml — emitted by claudemex generate
host: $host
generator_version: $gver
tier: $tier
generated_at: $now
tool: $tool
EOF
}

# write_kernel_meta <file> <K> <common_count> <host_csv>
write_kernel_meta() {
    local file="$1" k="$2" common_count="$3" host_csv="$4"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    {
        echo "# kernel-meta.yaml — emitted by claudemex merge"
        echo "generated_at: $now"
        echo "K_threshold: $k"
        echo "common_section_count: $common_count"
        echo "contributing_hosts:"
        while IFS=',' read -ra hosts; do
            for h in "${hosts[@]}"; do echo "  - $h"; done
        done <<< "$host_csv"
    } > "$file"
}

# read_meta_field <file> <field>
# For flat scalar fields only. Returns empty string if missing.
read_meta_field() {
    local file="$1" field="$2"
    # Use fixed-string grep with explicit anchor check to avoid regex injection
    # when field names contain regex metacharacters.
    grep -F -- "${field}:" "$file" 2>/dev/null \
        | grep -E "^${field}:" 2>/dev/null \
        | head -1 \
        | sed "s|^${field}:[[:space:]]*||"
}

# read_meta_list <file> <field>
# For "field:\n  - item1\n  - item2" lists. Prints one item per line.
# Note: uses 'inside' instead of 'in' as the awk state variable because
# 'in' is a reserved keyword in awk (used in 'for (x in array)').
read_meta_list() {
    local file="$1" field="$2"
    awk -v f="$field" '
        $0 ~ "^"f":[[:space:]]*$" { inside=1; next }
        inside && /^  - / { sub(/^  - /, ""); print; next }
        inside && /^[^ ]/ { inside=0 }
    ' "$file"
}
