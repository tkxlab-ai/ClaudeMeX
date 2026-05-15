# claudemex references

Background reading and external pointers for the ClaudeMeX prompt design.

## Inspirations baked into the prompt

- **Linus's Three Questions** (Linus Torvalds, paraphrased on LKML over
  years) — every proposal must answer "real problem? simpler way? what
  breaks?" before being presented.
- **Karpathy's four LLM coding postures** (Andrej Karpathy, blog & talks)
  — Think Before Coding / Simplicity First / Surgical Changes /
  Goal-Driven Execution. Embedded as anchors B.1–B.4 in COMMON+MAX rules.
- **Tacit Knowledge five** (Polanyi, applied to dev workflows) — Read the
  Room / Style Follows Repo / Convention over Configuration / Why over
  How / Memory is Tacit Knowledge. Embedded as anchors C.1–C.5.

## Adjacent toolchains

- **TKX gitx-release** (`~/.claude/skills/gitx-release/`) — the standard
  release pipeline this project uses. See `references/TKX_Git_Release_*`
  in that skill for the upstream policy.
- **TKX handoff** (`~/.claude/skills/handoff/`) — project handoff
  document spec; ClaudeMeX MAX tier rules reference HANDOFF.md as one of
  the canonical memory carriers (Tacit#5).

## See also

- `../SKILL.md` — when this skill triggers and how it executes.
- `../assets/example-output-pointer.md` — link to the public-safe COMMON
  example that ships under `Release/example-output/`.
