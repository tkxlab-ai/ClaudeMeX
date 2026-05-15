# Example output

The public-safe COMMON-tier example lives under
`<repo-root>/Release/example-output/`. It contains:

- `CLAUDE.md` — synthetic main configuration (~120 lines), keyed to the
  fictional machine `APPLE_M4_MAX` and developer `Alex Chen`
- `INDEX.md` — directory navigation
- `REPORT.md` — generation summary + verification check list
- `rules/` — the 10 standard COMMON-tier rule files
  (`01-identity.md` … `10-plugins-skills.md`)

Browse it before you run the generator on your own machine to know what
shape the output will take. Real generator runs produce the same
structure with your actual machine context, not the fictional one.

## Why is this not duplicated under skills/claudemex/assets/?

The example is large (~12 files) and serves a dual purpose:

1. End-user reference — bundled with each `Release/<v>/` artefact so
   downloaders see what the generator produces without running it.
2. Test fixture — `tests/test-llm-consistency.sh` reads it as a known-
   good baseline.

Duplicating it inside the skill bundle would inflate the `.skill`
package without adding access (the skill ships the prompt + scripts;
example-output is informational, lives at repo root).
