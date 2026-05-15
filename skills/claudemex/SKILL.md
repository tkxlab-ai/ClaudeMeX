---
name: claudemex
description: Scans Claude Code / Codex / Gemini / OpenCode sessions to generate per-machine CLAUDE.md (MIN/COMMON/MAX). Use whenever user wants to refresh CLAUDE.md, analyze CLI behavior, or 生成 / 更新 配置.
---

# ClaudeMeX — Claude Code Config Generator

## 何时触发 (When to trigger)

- User asks to "generate CLAUDE.md" / "set up Claude Code config" / "做一份 CLAUDE.md"
- User installs ClaudeMeX on a new machine and runs the prompt
- Periodic refresh ("re-run patch mode every two weeks") to capture
  behavioral drift in the user's working style
- (v1.1.0+) User asks to **merge** / **合并行为** / **跨设备汇总** /
  **behavior merge** ClaudeMeX outputs from multiple machines, or to
  **apply a kernel** / **deploy merged kernel** back to a host
  (see `docs/merge-guide.md`)

## 执行流程 (Execution flow / steps)

1. **Step 0 — Machine scan**: read `~/.claude/projects/`, plugins, sessions
2. **Step 1 — Tier select**: choose MIN / COMMON / MAX based on `$CCG_*` env
3. **Step 2 — Emit MAX baseline** (if applicable)
4. **Step 3 — Emit COMMON** (always; MIN/MAX both derive from it)
5. **Step 4 — Emit MIN** (subset of COMMON)
6. **Step 5 — Run gates**: `redact-scan.sh` + `structural-gate.sh`
7. **Step 6 — Deploy** (optional): `deploy.sh <TIER> ~/.claude/`

A meta-prompt that scans a developer's local Claude Code state (sessions,
plugins, projects) and produces a tier-aware `CLAUDE.md` configuration:

- **MIN** (~160 lines, ~17K tokens) — minimum baseline for a fresh laptop / CI
- **COMMON** (~480 lines, ~40K tokens) — daily driver across projects
- **MAX** (~1000+ lines, ~90K+ tokens) — machine-bound + project catalogue

The product is a Markdown prompt; the supporting toolchain (release gates,
deploy script, example output) lives under this skill.

## Where things live

| Path | Purpose |
|------|---------|
| `../TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md` (root) | Canonical generator prompt — what users feed to Claude Code |
| `../Release/v<X.Y.Z>/` | Self-contained release bundles (CHANGELOG / LICENSE / README / prompt + CHECKSUMS) |
| `../Release/example-output/` | Synthetic COMMON-tier example, renderable without running the generator |
| `../Release/lite-prompt-MIN.md` | 5-minute Quick Start template |
| `scripts/redact-scan.sh` | Pre-release redaction scanner (24 categories, BSD-grep portable) |
| `scripts/structural-gate.sh` | Structural verifier for generator outputs |
| `scripts/deploy.sh` | Deploy a generated tier to `~/.claude/` (honours `$CCG_PREFIX`) |
| `scripts/merge.sh` (v1.1.0+) | Combine N hosts' `outputs/` into common-kernel + per-machine extension via majority vote |
| `scripts/apply.sh` (v1.1.0+) | Deploy a merged kernel to this host's `~/.claude/CLAUDE.md` (default dry-run + backup) |
| `scripts/export.sh` / `scripts/import.sh` (v1.1.0+) | Tarball-based transport fallback when Syncthing/Gitea unavailable |
| `scripts/merge-report.sh` (v1.1.0+) | Re-print existing merge / drift reports |
| `../tests/run_all.sh` | Single test entrypoint — runs every `tests/test-*.sh` |

## How to use the skill

1. Open `TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md` (after `install.sh`) or
   `assets/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md` (after `.skill` unzip),
   copy the prompt, and paste it into a fresh Claude Code session in your
   project root.
2. The agent runs Step 0 (machine scan) → emits an `outputs/CLAUDE-CONF-<TIER>-<DATE>/`
   directory under your project root.
3. `bash scripts/deploy.sh <TIER> ~/.claude/` copies the latest tier into
   `~/.claude/`. The `$CCG_PREFIX` env var (default `CLAUDE-CONF`) controls
   which prefix the script looks for.
4. Re-run every two weeks in `patch` mode to capture behavioral drift.

## Release process

This skill follows the **TKX gitx-release** standard:

```
PROJECT_ROOT="$(pwd)" SKILL_NAME=claudemex \
  bash ~/.claude/skills/gitx-release/scripts/gitx-release.sh
```

The release pipeline runs `tests/run_all.sh`, builds a `.skill` package + a
reproducible source tarball, runs `release-sanitize.sh` against the staged
content, flattens docs, and writes `Release/<version>/`. It does **not**
tag, push, or create a GitHub Release — those are manual user actions.

## Non-Goals

- Not a runtime agent — the skill writes static configuration, not policy
  that the agent enforces at run time.
- Not a `~/.claude/CLAUDE.md` replacement on its own — users still edit and
  review the produced files before adopting them.
- Not bundled with the generated tiers themselves (this skill ships the
  generator and gates; the tiers are emitted into your project's
  `outputs/` directory and never flow back into this repo).

## License

MIT — see `LICENSE` in the project root.
