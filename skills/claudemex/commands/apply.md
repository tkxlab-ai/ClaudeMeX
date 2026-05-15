---
name: apply
description: Deploy a merged ClaudeMeX kernel to this host's ~/.claude/CLAUDE.md. Default behavior is dry-run; pass --apply to actually write (with backup).
---

# /apply — deploy a merged ClaudeMeX kernel to this machine

Activates `claudemex apply`. Renders `kernel/common-kernel/rules/` plus
this host's `kernel/per-machine-extension/<host>/rules/` into a single
`CLAUDE.md` at `--target-file` (default: `~/.claude/CLAUDE.md`).

## Usage

```
/apply --kernel=merged/2026-W18/                    # dry-run (prints diff)
/apply --kernel=merged/2026-W18/ --apply            # write (with backup)
/apply --kernel=merged/2026-W18/ --apply --force    # write, skip backup
```

## Behavior

- **Default = dry-run**: prints `diff -u` against existing target, does not write
- **--apply**: writes target. Existing file backed up to `.bak.<UTC-ts>` unless `--force`
- **Orphan host**: if local hostname has no `per-machine-extension/<host>/`
  entry, warns and renders common-kernel-only (no error)

See `docs/merge-guide.md` for the full lifecycle (generate → merge → apply).
