**English** | [简体中文](README.zh-CN.md)

# ClaudeMeX

> Your Claude Code, calibrated to you. One prompt → three tiers of config.

**Get started in under 5 minutes** [→ Quick Start](#quick-start)

## What is this?

ClaudeMeX scans your machine's Claude Code history and project landscape, then produces **three self-contained configuration tiers**:

| Need | Pick | ~Lines | First-run time |
|------|------|--------|----------------|
| Fresh machine / CI | **MIN** | 160 | < 1 min |
| Daily driver across projects | **COMMON** | 480 | 3–5 min |
| Machine with full project catalogue | **MAX** | 1000+ | 5–15 min |

## Installation

```bash
git clone https://github.com/tkxlab-ai/claude-code-config-generator.git
cd claude-code-config-generator
bash install.sh    # installs to ~/.claude/skills/claudemex/
```

Override the install location with `PREFIX=/your/path bash install.sh`.
Re-run `install.sh` to upgrade; `install.sh --uninstall` to remove. Full
options and troubleshooting in [INSTALL.md](INSTALL.md).

## Quick Start

### Option A: 5-min MIN-lite (fastest path)

1. Open `Release/lite-prompt-MIN.md` in any text editor
2. Copy the content between `<!-- COPY FROM HERE -->` and `<!-- COPY TO HERE -->`
3. Paste into `~/.claude/CLAUDE.md` (create the file if it doesn't exist)
4. Edit the placeholder values marked with `CCG_*` to match your setup

### Option B: Full generation via Claude Code

1. **Install Claude Code** (`npm i -g @anthropic-ai/claude-code`)
2. **Run `claude` in any directory**
3. **Paste `TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md`** into the chat
4. **Wait 5–15 minutes** for scan + generation
5. **Deploy** to `~/.claude/`:
   ```bash
   bash Release/deploy.sh MIN ~/.claude/
   # or COMMON, or MAX
   ```

### Which tier should I use?

```
┌─ Fresh Mac / container / CI? ──→ MIN ✅
│
├─ Daily use across projects? ───→ COMMON ✅
│
├─ Want project-specific rules? ─→ MAX ✅
│
└─ Not sure? Start with MIN (upgrade anytime)
```

## Tiers at a glance

| Feature | MIN | COMMON | MAX |
|---------|-----|--------|-----|
| Core rules | ✅ 7 | ✅ 10 | ✅ 10 |
| Project-specific rules | ❌ | ❌ | ✅ N |
| Linus 三问 | ✅ | ✅ | ✅ |
| Karpathy rules | ✅ | ✅ | ✅ |
| Tacit Knowledge | ✅ | ✅ | ✅ |
| Machine fingerprints | ❌ | ❌ | ✅ |
| Session history analysis | ❌ | ❌ | ✅ |
| Per-project style anchors | ❌ | ❌ | ✅ |

## Multi-machine merge (v1.1.0+)

Run ClaudeMeX on more than one machine? You can collect each machine's
output and produce a single **common-kernel** of cross-machine constants
(identity, decision framework, etc.) while keeping machine-specific
project archives in a per-host extension. Section-level majority vote
with `K = max(2, ⌈N/2⌉)`.

```bash
# On each machine, weekly:
claudemex generate --tier=MAX

# On any one machine (the merge node):
claudemex merge
less merged/<YYYY-WW>/drift-report.md   # review drift, decide promote/demote

# On each machine, after reviewing:
claudemex apply --kernel=merged/<YYYY-WW>/            # dry-run
claudemex apply --kernel=merged/<YYYY-WW>/ --apply    # write (with backup)
```

See [`docs/merge-guide.md`](docs/merge-guide.md) for the full guide,
including the drift-report format, transport options
(Syncthing / Gitea / `claudemex export` + `import`), and troubleshooting.

## Demo

<!-- GIF: 20-second screencast showing: terminal → claude → paste prompt → scan → deploy -->
> 📹 _Coming soon — 20s demo: terminal to deployed config_

## Pre-release safety

Every release runs `redact-scan.sh` (24+ categories) to catch:
- API keys, SSH keys, JWT tokens, GPG keys
- Cloud credentials (AWS, Aliyun, Tencent)
- Database URIs with passwords
- Package registry tokens (npm, PyPI, Docker)
- Personal emails, phone numbers, device IDs
- Private IP/domains, user paths

```bash
bash Release/redact-scan.sh Release/vX.Y.Z/
# Exit 0 = clean → safe to publish
# Exit 1 = violations → blocked
```



### How rules/ work

Claude Code loads `CLAUDE.md` from `~/.claude/` automatically. Rule files in `rules/` are **not auto-loaded** — they are reference documentation that you can merge into `CLAUDE.md` per-project:

```bash
bash Release/deploy.sh MIN ~/.claude/
```

Rules are numbered by domain (01-identity, 02-execution, etc.) for selective integration.
## Repository layout

```
.
├── README.md                                 ← this file
├── README.zh-CN.md                           ← Chinese readme
├── TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md    ← full generator prompt
├── Release/
│   ├── lite-prompt-MIN.md                   ← 60-line quick-start
│   ├── deploy.sh                            ← deploy tiers to target
│   ├── redact-scan.sh                       ← pre-release credential scanner
│   ├── structural-gate.sh                   ← pre-release structural verifier
│   ├── example-output/                      ← synthetic COMMON-tier example
│   └── vX.Y.Z/                              ← self-contained release bundles
├── outputs/                                  ← generated artifacts (gitignored, per machine)
│   ├── CLAUDE-CONF-MIN-YYYYMMDD/             ← prefix from $CCG_PREFIX (default: CLAUDE-CONF)
│   ├── CLAUDE-CONF-COMMON-YYYYMMDD/
│   ├── CLAUDE-CONF-MAX-YYYYMMDD/
│   └── translations/                         ← translated tier variants (not for deploy.sh)
└── tests/                                    ← test suites
```

## Contributing

PRs and issues welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
development setup, coding conventions, and PR checklist. Please run
`bash tests/run_all.sh` and `bash scripts/redact-scan.sh .` before
opening a PR.

Test scenarios and CI expectations: [TEST-SCENARIOS.md](TEST-SCENARIOS.md).

## License

MIT License · Free for personal and commercial use.
Copyright (c) 2026 TKXLAB.AI — https://github.com/tkxlab-ai

> If you integrate ClaudeMeX into your own workflows, a link back is appreciated.
