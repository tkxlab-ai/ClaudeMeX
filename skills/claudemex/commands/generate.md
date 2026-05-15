---
name: generate
description: Open the ClaudeMeX generator prompt and walk the user through producing a per-machine CLAUDE.md set in the requested tier (MIN, COMMON, or MAX).
---

# /generate — produce a per-machine CLAUDE.md tier

Activates the ClaudeMeX prompt-driven workflow. The agent reads
`TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md`, performs the local Claude Code
state scan (Step 0), then emits the requested tier under
`outputs/CLAUDE-CONF-<TIER>-<DATE>/`.

## Usage

```
/generate MIN     # ~160 lines, fastest path
/generate COMMON  # ~480 lines, daily driver
/generate MAX     # ~1000+ lines, machine-bound + project catalogue
```

If no tier is given, the agent picks based on `$CCG_*` environment
variables and the user's prior usage. The emitted directory is then
deployable via `bash scripts/deploy.sh <TIER> ~/.claude/`.

## Notes

- Run from a project root (the agent uses cwd to anchor scans).
- Re-running with `CCG_MODE=patch` produces incremental diffs against the
  most recent prior output rather than a full regeneration.
- Output is local-only; the prompt makes zero network calls of its own
  beyond Claude API traffic the user already initiated.
