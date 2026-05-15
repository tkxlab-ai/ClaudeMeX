#!/usr/bin/env bash
# render-claude.sh — Phase 1 markdown renderer for `claudemex apply --target=claude`
# Sourced as a library. Strict-mode options are the caller's responsibility;
# we do not mutate the caller's shell here.

# render_claude_md <kernel_dir> <host> <out_file>
# Concatenates common-kernel/rules/*.md (sorted) then
# per-machine-extension/<host>/rules/*.md (sorted). Adds banner separators.
# Returns non-zero if kernel_dir is missing common-kernel/.
render_claude_md() {
    local kernel_dir="$1" host="$2" out="$3"

    if [ ! -d "$kernel_dir/common-kernel" ]; then
        echo "render_claude_md: missing $kernel_dir/common-kernel" >&2
        return 1
    fi

    {
        echo "# CLAUDE.md — assembled by claudemex apply"
        echo "# kernel: $kernel_dir"
        echo "# host:   $host"
        echo "# generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo

        echo "<!-- ============ common-kernel ============ -->"
        echo
        if compgen -G "$kernel_dir/common-kernel/rules/*.md" >/dev/null; then
            local f
            while IFS= read -r f; do
                cat "$f"
                echo
            done < <(ls "$kernel_dir/common-kernel/rules/"*.md 2>/dev/null | sort)
        fi

        local ext_dir="$kernel_dir/per-machine-extension/$host/rules"
        if [ -d "$ext_dir" ] && compgen -G "$ext_dir/*.md" >/dev/null; then
            echo "<!-- ============ per-machine extension: $host ============ -->"
            echo
            local g
            while IFS= read -r g; do
                cat "$g"
                echo
            done < <(ls "$ext_dir/"*.md 2>/dev/null | sort)
        fi
    } > "$out"
}
