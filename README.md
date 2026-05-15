**English** | [简体中文](README.zh-CN.md)

![version](https://img.shields.io/badge/version-v1.3.3-blue)
![license](https://img.shields.io/badge/license-MIT-green)
![tests](https://img.shields.io/badge/tests-54%20pass%20%2F%200%20fail-brightgreen)
![audit](https://img.shields.io/badge/deep--audit-222%20checks-success)
![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)

# ClaudeMeX

> **Your AI coding assistant, calibrated to how _you_ actually work.**
> One prompt scans your real CLI history → a configuration tuned to your habits.

---

## Why does this exist?

Every AI coding CLI — Claude Code, OpenAI Codex, Gemini CLI, OpenCode — ships
knowing **nothing about you**. So everyone hand-writes a `CLAUDE.md` from
scratch. That approach breaks down:

| | Hand-written `CLAUDE.md` | ClaudeMeX |
|---|---|---|
| **Basis** | Guesswork — how you _think_ you work | Evidence — your measured session history |
| **Freshness** | Ages while habits change | Re-run every 2 weeks; tracks reality |
| **Multi-machine** | Laptop & desktop disagree | Majority-vote common-kernel + per-machine deltas |
| **Multi-tool** | Codex & Claude get different rules | One unified kernel across all 4 CLIs |
| **Privacy** | Manual, error-prone redaction | cwd auto-collapsed + 16-category scan gate |
| **Effort** | Hours of hand-tuning, repeated | One prompt, ~5–15 min, repeatable |

ClaudeMeX replaces that guesswork with **evidence**.

## What is ClaudeMeX?

A **meta-prompt + toolchain** that runs **entirely on your machine** and:

1. **Scans** your real local session history across all four CLI tools.
2. **Extracts** behavioral signals — corrections you actually make, tools you
   approve/reject, true time-of-day profile, tech mix, task distribution.
3. **Merges** them into one kernel with fuzzy de-dup, so "don't blind sed" /
   "禁止 sed 盲改" collapse into one weighted rule regardless of which tool.
4. **Renders** a tiered `CLAUDE.md` calibrated to that evidence.
5. **Deploys** it (with backup + privacy redaction gate), plus an
   opportunistic byte-equal copy to OpenCode.

Nothing is uploaded anywhere.

## What it produces (sample)

A scan distills your real corrections into a weighted, de-duplicated kernel
section (synthetic, redacted example):

```markdown
## §15 Behavioral rules (from 4-CLI session scan, 90-day corpus)

- Never blind-`sed` edits — read the file first  (×23, claude+codex)
- Always verify before deploy (curl/grep)         (×15, claude+opencode)
- Don't summarize unless asked                    (×11, gemini+claude)
- Static-allocate on embedded targets, no malloc  (×7,  codex)

## §16 Time-of-day profile (content timestamps, local TZ)
peak 22:00–01:00 (52%) · secondary 09:00–11:00 (high-focus C work)
```

You get this **derived from what you actually did** — not a blank template.

## What's new

| Version | Date | Highlights |
|---------|------|-----------|
| **v1.3.3** | 2026-05-15 | Re-pack on latest GitX release pipeline (deep audit 222 checks) |
| **v1.3.2** | 2026-05-14 | Step 0c multi-CLI inventory in prompt + pushy skill description |
| **v1.3.1** | 2026-05-13 | Multi-CLI behavior input: 4 readers + correction-extractor + Cat-16 redaction |
| **v1.3.0** | 2026-05-11 | TKX unified install standard |

Full history: [Releases](../../releases) · [CHANGELOG](Release/CHANGELOG.md).

## Three tiers

| Need | Tier | ~Lines | First-run | Token budget |
|------|------|--------|-----------|--------------|
| Fresh machine / CI / Codex 32 KiB cap | **MIN** | ~160 | < 1 min | ~17 K |
| Daily driver across projects | **COMMON** | ~480 | 3–5 min | ~40 K |
| Main machine with full project catalogue | **MAX** | 1000+ | 5–15 min | ~90 K+ |

MIN ⊂ COMMON ⊂ MAX. Move tiers without rewriting anything.

## Multi-CLI behavior input (v1.3+)

| Tool | Source scanned |
|------|----------------|
| **Claude Code** | `~/.claude/projects/*/*.jsonl` |
| **OpenAI Codex** | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` + `session_index.jsonl` |
| **Google Gemini** | `~/.gemini/history/<user>/*.json` (opportunistic) |
| **OpenCode** | `~/.local/share/opencode/opencode.db` (SQLite) |

`correction-extractor` fuzzy-merges correction phrases (token Jaccard ≥ 0.7,
bilingual zh/en markers) into `merged-signals.md`.

> **Calibration knob.** Default markers match declarative directives
> (`don't X`, `必须 X`). Indirect style? Tune
> `scripts/correction-extractor.sh`'s marker lists to your corpus.

## Privacy & safety

- **cwd redaction** — `/Users/<self>/…` → `~/…`, `/Users/<other>/…` →
  `<other>:~/…`; applied by every reader before disk.
- **16-category scanner** — flags cwd leaks, OAuth tokens, session-id UUIDs,
  credential paths; fail-closed on every artifact.
- **Never exfiltrated** — `behavior-raw/` is gitignored + sanitize-ignored;
  never committed, never bundled.
- **Backup before deploy** — `apply.sh` backs up + defaults to dry-run.

## Prerequisites

- **Claude Code** (`npm i -g @anthropic-ai/claude-code`) — the host CLI
- **bash 3.2+**, **python3** (stdlib only), **git**
- **sqlite3** CLI — optional; only for the OpenCode reader (skips gracefully)
- macOS or Linux

## Installation

```bash
git clone https://github.com/tkxlab-ai/ClaudeMeX.git
cd ClaudeMeX
bash install.sh                     # → ~/.claude/skills/claudemex/
PREFIX=/your/path bash install.sh   # custom location
bash install.sh --uninstall         # remove
```

Re-run `install.sh` to upgrade. Full options + 8-section troubleshooting in
[INSTALL.md](INSTALL.md).

## Quick start

**Fastest (5-min MIN-lite):** open `Release/lite-prompt-MIN.md`, copy the
marked block into `~/.claude/CLAUDE.md`, edit the `CCG_*` placeholders.

**Full generation:**

1. `npm i -g @anthropic-ai/claude-code`
2. Run `claude` in any directory
3. Paste `TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md` into the chat (or use the
   `/generate` skill command after `install.sh`)
4. Wait for scan + generation (5–15 min)
5. Deploy: `bash Release/deploy.sh MIN ~/.claude/` (or `COMMON` / `MAX`)

## Multi-machine merge

Run the generator on each machine (the `/generate` skill command inside
Claude Code, or paste `TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md`), sync the
`outputs/` directories (Syncthing / git / tarball), then on any one machine:

```bash
bash scripts/merge.sh --from=outputs --hosts=hostA,hostB
bash scripts/apply.sh --target=claude --apply   # deploy merged kernel
```

Section-level majority vote → `common-kernel/` (agreed rules) +
`per-machine-extension/` (machine-specific deltas).

## Repository layout

```
TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md   meta-prompt you paste into the CLI
skills/claudemex/                       installable skill bundle
scripts/                                readers, extractor, merge, apply, redact-scan
tests/                                  6-tier test pyramid
Release/claudemex-vX.Y.Z/               release bundles (.skill + checksums + SBOM)
docs/                                   design specs, plans, v1.4 roadmap
```

## Testing

Six-tier pyramid gates every release: **Unit → Property-based → Adversarial
→ End-to-end → Regression hard-gate → independent red-team review**. Each
release ships a frozen baseline + a 200+ check deep-audit via the GitX
pipeline.

## Distribution

Public distribution is **release-artifact only**: download
`claudemex-vX.Y.Z.skill` from [Releases](../../releases) (ships `.skill`,
`checksums.txt`, CycloneDX `sbom.cyclonedx.json`). Full source tree is in a
private mirror.

## License

MIT © 2026 TKXLAB.AI — see [LICENSE](LICENSE).
