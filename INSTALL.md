# INSTALL — Complete install / upgrade / uninstall / maintenance reference for claudemex

> README.md describes **what ClaudeMeX is** (per-machine CLAUDE.md generator with MIN / COMMON / MAX tiers + redaction scanner + structural gate + deployer + multi-machine merge). This document describes **how to install, upgrade, uninstall, and maintain it** — every command annotated.

---

## 📖 Table of Contents

- [0. File location cheat sheet](#0-file-location-cheat-sheet)
- [1. Install](#1-install)
  - [1.1 Method A — Source + install.sh (recommended)](#11-method-a--source--installsh-recommended)
  - [1.2 Method B — Single `.skill` file](#12-method-b--single-skill-file)
  - [1.3 Method C — Manual directory copy](#13-method-c--manual-directory-copy)
  - [1.4 Method D — curl one-liner](#14-method-d--curl-one-liner)
  - [1.5 Remote / SSH deployment](#15-remote--ssh-deployment)
- [2. First-time project initialization](#2-first-time-project-initialization)
- [3. Upgrade](#3-upgrade)
- [4. Uninstall](#4-uninstall)
- [5. Verify / Self-check](#5-verify--self-check)
- [6. Release (developers)](#6-release-developers)
- [7. Daily maintenance commands](#7-daily-maintenance-commands)
- [8. Troubleshooting](#8-troubleshooting)

---

## 0. File location cheat sheet

```
~/.claude/skills/claudemex/             # Canonical install (PREFIX, overridable)
├── SKILL.md                            # Skill entry / system prompt
├── VERSION                             # Sidecar version (v1.x.y)
├── TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md  # The generator prompt — paste into a Claude session
├── README.md / INSTALL.md / LICENSE / CONTRIBUTING.md / TEST-SCENARIOS.md
└── scripts/                            # Helpers
    ├── deploy.sh                       # Deploy merged CLAUDE.md to host
    ├── apply.sh                        # `apply` subcommand
    ├── merge.sh                        # Multi-machine merge
    ├── import.sh / export.sh           # Transport tarballs between hosts
    ├── merge-report.sh                 # Re-print merge / drift reports
    ├── redact-scan.sh                  # Pre-merge redaction scanner
    ├── structural-gate.sh              # Gate generated CLAUDE.md schema
    ├── emit-sbom.sh / emit-token-usage.sh
    └── lib/install-output-style.sh     # Unified install.sh output helper

~/.claude/commands/                     # Slash command shims (Claude Code)
├── generate.md                         # /generate — open the generator prompt
├── merge.md                            # /merge — cross-machine merge
├── apply.md                            # /apply — deploy merged kernel
├── export.md / import.md               # /export, /import — transport
└── merge-report.md                     # /merge-report — re-print reports

~/.claude/CLAUDE.md                     # Final deployed kernel (NEVER touched by install.sh
                                        # directly; /apply is the only thing that writes here,
                                        # with a backup at CLAUDE.md.bak)
```

> The skill never writes `~/.claude/CLAUDE.md` directly. `install.sh` only stages the generator prompt + helper scripts. `/apply` writes the kernel after `/merge` has produced a `merged/<YYYY-WW>/kernel.md`.

---

## 1. Install

### 1.1 Method A — Source + install.sh (recommended)

For long-term upgrades, team deployment, or CI.

```bash
git clone https://github.com/tkxlab-ai/ClaudeMeX.git
cd ClaudeMeX
bash install.sh                  # Install to default ~/.claude/skills/claudemex/
PREFIX=/opt/claudemex bash install.sh   # Custom prefix
bash install.sh --dry-run        # Preview without writing
bash install.sh --force          # Overwrite an existing non-empty PREFIX
bash install.sh --uninstall      # Remove the installed copy
bash install.sh --help           # Full flag reference
```

The installer renders the unified TKX banner (output of `bash install.sh` — the live install path):

```
===============================================================
  📦  claudemex Installation  v1.3.0
===============================================================
🔍  Checkpoint 1/3 — Preflight
    ✅ Source : <repo-root>
    ✅ Target : ~/.claude/skills/claudemex
📂  Checkpoint 2/3 — Install
    ✅ Generator prompt + helper scripts + commands shimmed
✓   Checkpoint 3/3 — Validation
    ✅ Installed at ~/.claude/skills/claudemex
===============================================================
  🎉  claudemex v1.3.0 installed
===============================================================
```

Visual structure identical to gitx-release v1.5.0 / mac-release v0.2.0 / handoff v2.2.0 / 1by1 v0.7.0.

### 1.2 Method B — Single `.skill` file

For out-of-band distribution (email, shared drive, scp).

```bash
mkdir -p ~/.claude/skills
unzip -o claudemex-v<VERSION>.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/claudemex/scripts/*.sh
```

### 1.3 Method C — Manual directory copy

Maximum transparency, zero install script.

```bash
cp -R skills/claudemex ~/.claude/skills/claudemex
chmod +x ~/.claude/skills/claudemex/scripts/*.sh
cp commands/*.md ~/.claude/commands/
```

### 1.4 Method D — curl one-liner

**Not supported as a pure `curl install.sh | bash` one-liner.** The installer requires the full bundle (TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md, SKILL.md, scripts/, scripts/lib/install-output-style.sh, commands/). Use **Method B** or **Method A** instead.

If a fetch-and-install one-liner is needed:

```bash
VER=v1.3.0
curl -fsSL https://<your-release-host>/releases/claudemex-${VER}/claudemex-${VER}.skill -o /tmp/cmx.skill
unzip -o /tmp/cmx.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/claudemex/scripts/*.sh
```

### 1.5 Remote / SSH deployment

```bash
# Push source then install
scp -r ClaudeMeX/ user@remote:~/
ssh user@remote 'cd ~/ClaudeMeX && bash install.sh'

# Or push .skill bundle
scp Release/claudemex-v<VERSION>/claudemex-v<VERSION>.skill user@remote:~/
ssh user@remote 'mkdir -p ~/.claude/skills && unzip -o ~/claudemex-v<VERSION>.skill -d ~/.claude/skills/'
```

---

## 2. First-time project initialization

ClaudeMeX is host-level, not project-level — there's no per-project init. The workflow is:

### 2.1 Generate a per-machine kernel

In Claude Code, opened anywhere:

```
/generate              # then choose MIN / COMMON / MAX tier
```

This drives the interactive generator prompt and writes outputs under `outputs/<host>-<timestamp>/`.

### 2.2 (Optional) Set up environment variables

Some helpers read env vars to opt into stricter behavior:

```bash
export CLAUDEMEX_REDACT_STRICT=1       # Treat every redaction hit as a hard FAIL
export CLAUDEMEX_GATE_STRICT=1         # Treat schema warnings as hard FAILs
export CLAUDEMEX_MERGE_TIE_BREAKER=newest   # On merge ties prefer the newest contribution
```

Defaults are sane for first-time users; set these only if you've read what they do.

### 2.3 Verify the bundled prompt

```bash
ls -la ~/.claude/skills/claudemex/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md
```

This file is the canonical artefact. Copy-paste it into a Claude session to bootstrap `/generate` if the slash command isn't yet registered.

---

## 3. Upgrade

### 3.1 Source users

```bash
cd ~/ClaudeMeX
git pull
bash install.sh --force          # idempotent re-install
```

> The merged `~/.claude/CLAUDE.md` (your deployed kernel) is NEVER touched by `install.sh`. Only `/apply` writes to it, and `/apply` always creates a `~/.claude/CLAUDE.md.bak` before overwriting.

### 3.2 `.skill` single-file users

```bash
unzip -o claudemex-v<NEW>.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/claudemex/scripts/*.sh
```

### 3.3 Re-deploy after upgrade

The skill body changes but your deployed kernel doesn't auto-update. Re-run the workflow:

```
/generate   # if your generator-prompt changed semantically
/merge      # if multi-machine kernel changed
/apply      # deploy the new kernel; old one backed up to ~/.claude/CLAUDE.md.bak
```

### 3.4 Post-upgrade verification

```bash
cat ~/.claude/skills/claudemex/VERSION       # → v<NEW>
bash ~/.claude/skills/claudemex/scripts/structural-gate.sh --help
```

---

## 4. Uninstall

### 4.1 Full uninstall (keeps generated outputs + deployed kernel)

```bash
bash install.sh --uninstall
```

Removes:
- `~/.claude/skills/claudemex/` (skill body + scripts + bundled prompt)

**Preserves:**
- `~/.claude/CLAUDE.md` (your deployed kernel — separate from the skill body)
- `outputs/<host>-<timestamp>/` directories in any project where you ran `/generate`
- `merged/<YYYY-WW>/` directories from past merges

### 4.2 Remove slash command shims

```bash
rm -f ~/.claude/commands/generate.md ~/.claude/commands/merge.md \
      ~/.claude/commands/apply.md ~/.claude/commands/export.md \
      ~/.claude/commands/import.md ~/.claude/commands/merge-report.md
```

### 4.3 Wipe deployed kernel + outputs (DESTRUCTIVE)

```bash
# Optional: restore from backup if /apply made one
mv ~/.claude/CLAUDE.md.bak ~/.claude/CLAUDE.md
# Or delete the kernel entirely (Claude Code will use built-in defaults)
rm ~/.claude/CLAUDE.md

# Per-project outputs and merge results
rm -rf outputs/ merged/
```

> Removing the deployed kernel reverts Claude Code to its built-in defaults. The skill keeps a `.bak` from the last `/apply` operation; restore that if you change your mind.

---

## 5. Verify / Self-check

### 5.1 Inside Claude Code

```
/                    # /generate / /merge / /apply / /export / /import / /merge-report should appear
```

### 5.2 Command line

```bash
# Check skill files
ls ~/.claude/skills/claudemex/SKILL.md && echo "skill present"
ls ~/.claude/skills/claudemex/TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md && echo "prompt present"

# Run structural gate on a sample output (if you have one)
bash ~/.claude/skills/claudemex/scripts/structural-gate.sh /path/to/outputs/<host>/

# Redaction scanner self-check
bash ~/.claude/skills/claudemex/scripts/redact-scan.sh --help
```

---

## 6. Release (developers)

### 6.1 One command

ClaudeMeX is shipped via gitx-release (the TKX meta-skill):

```bash
PROJECT_ROOT="$(pwd)" PROJECT_NAME=claudemex SKILL_NAME=claudemex \
  bash ~/.agents/skills/gitx-release/scripts/release.sh v<VERSION>
```

### 6.2 What the gitx-release pipeline does

1. Preflight (version consistency, CHANGELOG gate)
2. Run regression tests (`bash tests/run_all.sh`)
3. Dual-source byte-identical check (root vs `skills/claudemex/`)
4. Build `.skill` + source tarball + full tarball
5. Sanity scan (staging + bundle, both must pass)
6. Flatten docs + generate attestations (SBOM + TOKEN_USAGE)
7. Deep Audit (40+ checks, includes §0b unified-install-standard gate)
8. Atomic `Release/latest` symlink update

### 6.3 Sanity is unskippable

No `FORCE=1` bypass. Failure aborts release with non-zero exit.

---

## 7. Daily maintenance commands

### 7.1 Re-run the redaction scanner on outputs/

```bash
bash ~/.claude/skills/claudemex/scripts/redact-scan.sh outputs/<host>/
```

### 7.2 Re-run the structural gate

```bash
bash ~/.claude/skills/claudemex/scripts/structural-gate.sh outputs/<host>/
```

### 7.3 Re-print merge / drift reports without re-merging

```bash
bash ~/.claude/skills/claudemex/scripts/merge-report.sh merged/<YYYY-WW>/
```

### 7.4 Pack outputs for transport (no Syncthing / Gitea)

```bash
bash ~/.claude/skills/claudemex/scripts/export.sh outputs/<host>/
# Produces a hardened tarball with manifest + sha256
```

### 7.5 Import an exported tarball on the merge node

```bash
bash ~/.claude/skills/claudemex/scripts/import.sh /path/to/transport.tar.gz
# Validates against malicious tarball patterns (path traversal / symlinks / size bombs / setuid)
```

---

## 8. Troubleshooting

### 8.1 `/generate` / `/merge` not appearing in Claude Code

```bash
ls -la ~/.claude/skills/claudemex/SKILL.md      # confirm install
ls ~/.claude/commands/generate.md ~/.claude/commands/merge.md
# Inside Claude Code: /reload-plugins
```

If shims are missing, re-run `bash install.sh`.

### 8.2 "PREFIX exists and is not empty"

```bash
bash install.sh --force           # overwrite
# Or:
PREFIX=/different/path bash install.sh
```

### 8.3 `/apply` reports "Cannot find merged/<YYYY-WW>/kernel.md"

Run `/merge` first. `/apply` writes the kernel from a previously-merged result; it does not generate one.

### 8.4 Restore the previous deployed kernel

```bash
mv ~/.claude/CLAUDE.md.bak ~/.claude/CLAUDE.md
# `/apply` always creates a fresh .bak before overwriting
```

### 8.5 `redact-scan` keeps failing on a known-good output

The scanner is strict by design. Add the false-positive pattern to an allowlist:

```bash
# Inspect what redact-scan found
bash ~/.claude/skills/claudemex/scripts/redact-scan.sh -v outputs/<host>/
# Then add the literal to outputs/<host>/.redact-ignore (one regex per line)
```

### 8.6 Transport tarball rejected by `import.sh`

`import.sh` is hardened against malicious tarballs (path traversal, symlinks, size bombs, setuid bits). If a legitimate tarball is rejected:

```bash
bash ~/.claude/skills/claudemex/scripts/import.sh --verify-only /path/to/transport.tar.gz
# Inspect the rejected entry; either fix at the source host or whitelist if safe.
```

---

More design context in [README.md](./README.md).
