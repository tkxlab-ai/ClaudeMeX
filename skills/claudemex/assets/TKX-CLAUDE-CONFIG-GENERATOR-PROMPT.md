# ClaudeMeX — Claude Code Config Generator

> **Your Claude, calibrated to you.** One prompt that scans your machine and produces three tiers of `CLAUDE.md` + `rules/` configuration for Claude Code.
> Licensed under **MIT**. Works on macOS and Linux.

---

## MIT License

```
Copyright (c) 2026 TKXLAB.AI - https://github.com/tkxlab-ai

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Privacy & data handling

This generator runs **entirely on your local machine** with zero added network egress:

- All scanning happens on your filesystem (`~/.claude/`, sync roots, `~/coding/` or similar local dev mirror, `~/Desktop/`, `~/Documents/`). No cloud upload, no telemetry, no third-party API calls originate from the generator itself.
- Credential redaction runs locally **before** content enters the LLM context window (see `Credential / secret redaction list` below — 20+ patterns including API keys, SSH private keys, OAuth tokens, plaintext passwords, IPs, hostnames, emails).
- Output files land on your disk only; nothing is published or mirrored externally by this prompt.
- The only thing leaving your machine is your **existing** Claude Code traffic (prompt + scan results) to Anthropic's API — governed by Anthropic's privacy policy, unchanged by this generator.

**Threat-model opt-outs** (explicit env var or in-session confirmation required): users on personal / trusted-device scenarios may relax defaults (keep plaintext server IPs / hostnames on the grounds that firewall + key-only SSH reduces the leak value). Defaults stay conservative.

---

## Why this exists

Claude Code is powerful on a fresh machine, but it **doesn't know anything about you** — your projects, your tools, your past decisions, the traps you've already learned. Every new session starts from zero. Over time you end up re-explaining the same context, re-hitting the same pitfalls, and watching the agent confabulate field names and configs you've debugged a dozen times before.

This generator fixes that in one pass:

1. **Scan** — it reads the signals Claude would otherwise miss: active projects, memory trails, sync roots, daily usage patterns, the soul files of any agent frameworks you run.
2. **Compile** — it compresses those signals into three configuration tiers (**MIN** for fresh machines / containers / CI, **COMMON** for portable daily work, **MAX** for a daily-driver machine with full project catalogue), each a self-contained `CLAUDE.md` + `rules/` bundle.
3. **Anchor** — it embeds three public-domain principle groups (Linus's Three Questions for decisions, Karpathy's 4 LLM coding rules for behavior, Tacit Knowledge 5 for context) so every machine you configure shares the same spine.

**The outcome**: configure machine A once; machine B/C/D get a portable baseline in one copy-paste; containers and CI get the stripped-down MIN contract. Your tacit knowledge becomes portable and your agent stops starting from zero.

---

## What this produces

Three configuration tiers, each a self-contained directory:

| Tier | CLAUDE.md | rules/ | Total tokens (est.) | When to use |
|------|-----------|--------|---------------------|-------------|
| **MIN** | ~160 lines | 7 files | ~17K | Minimum contract for a fresh machine / container / CI |
| **COMMON** | ~480 lines | 10 files | ~40K | Cross-project baseline for daily work |
| **MAX** | ~1000+ lines | 10 base + N project-specific | ~90K+ | Machine-bound with your project catalogue |

### Which tier do I need?

Answer in order — the first "Yes" wins:

1. **Fresh machine, container, or CI runner with no prior Claude history?** → **MIN**
2. **You want one portable config that works on every machine you own?** → **COMMON** (ship it to all of them, skip MAX)
3. **This is your daily-driver machine and you want Claude to catalogue your projects + memory system?** → **MAX**
4. **Can't decide?** → Start with **COMMON**. It's the safest default; re-run the generator later with the same env vars to upgrade to MAX in place.

> Upgrading MIN → COMMON → MAX is a strict content superset (COMMON contains everything MIN does, plus more; see the MIN subset invariant in the Embedding Map section below), so downgrading is just deleting the machine-bound appendix — no data migration needed. Note: file names differ between tiers — see the Numbering note in Step 2.5 for the rename step that `deploy.sh` handles.

All three embed the same foundation:

- **Linus's Three Questions** — pre-decision gate
- **Karpathy's 4 LLM coding rules** — Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution
- **Tacit Knowledge 5 principles** — Read the Room / Style Follows Repo / Convention over Configuration / Why > How / Memory is Tacit Knowledge
- **MIT License-compatible** — no proprietary dependencies, no network calls

The generator ships a **two-phase review system** for the MIN tier: Phase 1 is a mandatory mechanical gate (anchor-phrase + structural checks, CI-runnable); Phase 2 is an optional three-persona self-review framing (Linus / Hickey / Polanyi as lenses). Running Phase 2 inside a single model session is a thinking discipline, not an independent audit — full disclaimer and upgrade path inside the prompt.

---

## Customization hooks (all optional env vars)

| Variable | Default | Effect |
|----------|---------|--------|
| `CCG_PREFIX` | `CLAUDE-CONF` | Output directory prefix |
| `CCG_MACHINE_CODE` | auto-detected from hostname (`scutil --get LocalHostName`) | Machine identifier for MAX tier output directory name |
| `CCG_SALUTATION` | (none) | Optional salutation the assistant uses for you |
| `CCG_START_MARKER` | (none) | Optional first visible character in every reply |
| `CCG_LANGUAGE` | match user input | Default reply language |

All customization is **opt-in**. Without env vars the generated config is language-neutral and has no salutation or start-marker constraints.

---

## How to use

1. Open Claude Code on the target machine
2. (Optional) `export CCG_PREFIX=MYCONF`, `export CCG_SALUTATION="Captain"`, etc.
3. Copy the prompt block below into Claude Code
4. Wait 5–15 minutes for scan + generation

---

## The prompt

> **Instructions**: Copy the entire fenced code block below (everything between the four-backtick fence) into Claude Code. The block is bracketed by `=== COPY FROM HERE ===` and `=== COPY TO HERE ===` as visual anchors — those marker lines are comments inside the prompt and safe to include. The outer fence uses four backticks so inner three-backtick code blocks render as literal text (safe for copy-paste).

````
=== COPY FROM HERE ===

Scan this machine's Claude memory, session metadata, and all development projects. Generate three tiers of Claude Code configuration: MIN (minimum contract), COMMON (strategic baseline), and MAX (machine-bound full version).

## Progress indicators (emit at the start of each step)

Emit a one-line status marker at the start of each step so the user knows generation is alive (5–15 min total wall-time is normal):

- `🔍 STEP 0/3: Scanning session metadata and sync roots...` (est. 30–90s)
- `🔍 STEP 1/3: Deep-scanning projects and memory...` (est. 2–5 min)
- `🧠 DRAFTING COMMON base (internal source of truth — see Generation strategy below)...`
- `📦 STEP 2/3: Emitting MAX tier (COMMON base + machine-bound appendix)...` (est. 2–4 min)
- `📦 STEP 2.5/3: Emitting MIN tier (subset of COMMON)...` (est. 1–2 min)
- `📦 STEP 3/3: Flushing COMMON tier + running three-layer verification...` (est. 1–2 min)
- `✅ DONE: Generated <N> files across 3 tiers at <path>`

If any single step exceeds 2× its estimate, emit `⏳ STILL WORKING: <current sub-task>` to confirm liveness rather than staying silent.

## Step 0: Session metadata + sync-root inventory + behavioral scan

### Step 0a: Metadata (fast)

1. Scan `~/.claude/projects/*/`, count sessions / total size / last mtime per project
2. Scan any agent-workspace logs if present (e.g. `~/.<agent-home>/workspace-*/logs/`)
3. `find ~/.claude/projects -type f -name "*.jsonl" -mtime -90` (path argument required on both BSD and GNU find; `-type f` required) to list projects active in last 90 days plus hourly-activity distribution
4. Flag "hidden projects" that have >= 10 sessions but aren't in any known project catalogue
5. **Sync-root identification**:
   - Scan `~/`, `~/Library/CloudStorage/*`, `~/iCloud*` for top-level sync roots
   - Directories containing `.stfolder` / `.stignore` / `.stversions` -> **Syncthing sync root** (highest priority, cross-device single source of truth)
   - iCloud / Dropbox / OneDrive / Google Drive -> **cloud sync root** (secondary priority)
6. **Multi-device collaboration profile**:
   - Count `.sync-conflict-*` files + device ID distribution
   - High-frequency entries in `.stversions/` -> "collaboration hotspot" files
   - Deduplicate device IDs and list them

### Step 0b: JSONL behavioral scan (full mode — runs after 0a, takes 5–20 min depending on corpus size)

**Purpose**: extract behavioral signals from session content — correction patterns, tool preferences, task distribution, true time-of-day profile. This step reads JSONL content via targeted grep; it never loads full file content into context.

**Scope**: all `.jsonl` files found in Step 0a (last 90 days). Skip files > 50 MB individually (record to `skipped.log`).

**Credential redaction**: before any extracted string enters the output, pipe through the redaction filter below. Never emit raw API keys, IPs, hostnames, email addresses, or tokens into `session-inventory.md`.

```bash
# Redaction filter — apply to all grep output before writing to output
sed -E \
  -e 's/\b(sk-[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{35,}|ghp_[A-Za-z0-9]{36,}|xoxb-[A-Za-z0-9-]+)\b/[REDACTED_KEY]/g' \
  -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/[REDACTED_IP]/g' \
  -e 's/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/[REDACTED_EMAIL]/g'
```

**Signal 1 — Correction patterns** (behavioral anti-patterns to encode in rules):
```bash
find ~/.claude/projects -type f -name "*.jsonl" -mtime -90 \
  | xargs grep -hiE \
    '"(content|text)"[[:space:]]*:[[:space:]]*"[^"]{0,200}(don'\''t|do not|stop|undo|revert|wrong|no,|不要|别|错了|改回)[^"]{0,200}"' \
    2>/dev/null \
  | grep -oiE '(don'\''t [^"]{5,60}|do not [^"]{5,60}|stop [^"]{5,60}|不要[^"]{3,30}|别[^"]{3,30}|错了[^"]{3,30})' \
  | sort | uniq -c | sort -rn | head -30
```
- Phrases appearing **≥ 2 times** = correction signal candidate
- Group semantically similar phrases (e.g. "don't summarize" / "stop summarizing" / "no summary" → one entry)
- Output: top-15 signals with frequency + one representative quote (redacted)

**Signal 2 — Tool approval / rejection ratio**:
```bash
find ~/.claude/projects -type f -name "*.jsonl" -mtime -90 \
  | xargs grep -hiE '"type"[[:space:]]*:[[:space:]]*"tool_(result|use)"' 2>/dev/null \
  | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' \
  | sort | uniq -c | sort -rn | head -20
```
Cross-reference with rejection signals (`"error"`, `"denied"`, `"permission"`) to compute per-tool approval rate. Output: top-10 tools by usage + any tool with rejection rate > 20%.

**Signal 3 — Task type distribution** (first user message per session):
```bash
find ~/.claude/projects -type f -name "*.jsonl" -mtime -90 \
  | while read f; do
      grep -m1 '"role"[[:space:]]*:[[:space:]]*"user"' "$f" 2>/dev/null
    done \
  | grep -oiE '"(content|text)"[[:space:]]*:[[:space:]]*"[^"]{10,120}"' \
  | grep -oiE '(fix|debug|add|create|refactor|explain|review|deploy|write|update|search|analyze|generate)[a-z ]{0,30}' \
  | sort | uniq -c | sort -rn | head -15
```
Classify into buckets: `bug-fix / feature / refactor / explain / review / deploy / research / config`. Output: percentage breakdown across 90-day corpus.

**Signal 4 — True time-of-day profile** (from content timestamps, not file mtime):
```bash
find ~/.claude/projects -type f -name "*.jsonl" -mtime -90 \
  | xargs grep -hoE '"(created_at|timestamp)"[[:space:]]*:[[:space:]]*"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}' \
    2>/dev/null \
  | grep -oE 'T[0-9]{2}' | sort | uniq -c | sort -k2 -n
```
Convert UTC hours → local timezone (read `TZ` env var or `/etc/localtime`). Output: 24-hour histogram, identify primary peak window and secondary peak (if any). **This supersedes any mtime-based time profile from Step 0a** — content timestamps are authoritative (lesson from M1 v1→v2 correction: mtime reflects sync time, not work time).

**Signal 5 — Technology / language frequency**:
```bash
find ~/.claude/projects -type f -name "*.jsonl" -mtime -90 \
  | xargs grep -hiE '"(content|text)"[[:space:]]*:[[:space:]]*"[^"]{0,300}"' 2>/dev/null \
  | grep -oiE '\b(python|typescript|javascript|golang|rust|swift|c\+\+|bash|react|next\.?js|fastapi|docker|kubernetes|postgres|sqlite|redis)\b' \
  | sort | uniq -c | sort -rn | head -20
```
Output: top-10 technologies by mention frequency — feeds §5 Code conventions and §13 Toolchain sections.

**Step 0b output** — append a `## Behavioral Signals` section to `session-inventory.md`:
```
## Behavioral Signals (from JSONL content scan — 90-day corpus)

### Correction Patterns (top-15, ≥2 occurrences)
| Frequency | Signal | Representative quote |
|-----------|--------|----------------------|
| ...       | ...    | "..."                |

### Tool Usage (top-10 by frequency)
| Tool | Uses | Rejection rate |
|------|------|----------------|

### Task Type Distribution
bug-fix ██████ 32% | feature ████ 24% | explain ███ 18% | ...

### Time-of-Day Profile (content timestamps, local TZ)
00 01 02 ... 23
▁  ▁  ▁  ... ▇  (histogram)
Primary peak: HH:00–HH:59 local  |  Secondary peak: HH:00–HH:59 local

### Technology Frequency (top-10)
| Technology | Mentions |
```

Output: `session-inventory.md` (activity ranking, time-of-day profile from content timestamps, hidden-project list, sync-root list, device profile, collaboration hotspots, **behavioral signals**).

### Step 0c: Multi-CLI behavior scan (v1.3+ — Claude / Codex / Gemini / OpenCode)

**Purpose**: extend Step 0b's Claude-only correction-pattern extraction across all 4 installed CLI tools when they exist on the host. Each tool emits its own jsonl shape; the v1.3 reader scripts normalize to a unified schema under `outputs/<host>-YYYYMMDD/behavior-raw/`.

**Source layout** (skip readers whose source dir is absent):
- Claude Code → `~/.claude/projects/*/*.jsonl` → `scripts/behavior-scan-claude.sh`
- OpenAI Codex CLI → `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` + `~/.codex/session_index.jsonl` → `scripts/behavior-scan-codex.sh`
- Google Gemini CLI → `~/.gemini/history/<user>/*.json` (opportunistic; current corpus often empty) → `scripts/behavior-scan-gemini.sh`
- OpenCode → `~/.local/share/opencode/opencode.db` (SQLite; requires `sqlite3` CLI) → `scripts/behavior-scan-opencode.sh`

**Pipeline**:

```bash
out="outputs/<host>-$(date +%Y%m%d)/behavior-raw"
mkdir -p "$out"
bash scripts/behavior-scan-claude.sh   --out-dir="$out"
bash scripts/behavior-scan-codex.sh    --out-dir="$out"
bash scripts/behavior-scan-gemini.sh   --out-dir="$out"
bash scripts/behavior-scan-opencode.sh --out-dir="$out"
# Merge correction signals across all 4 streams (token Jaccard ≥ 0.7 fuzzy dedup):
bash scripts/correction-extractor.sh --src="$out" --out="outputs/<host>-$(date +%Y%m%d)/merged-signals.md"
```

Each reader writes a single jsonl file (`claude.jsonl` / `codex.jsonl` / `gemini.jsonl` / `opencode.jsonl`) following the unified schema `{ts, tool, kind, text, cwd, session_id}`. `merged-signals.md` is the deduped correction-phrase bullet list to inject into `§15 / §16` of the generated kernel.

**§安全 — cwd 脱敏 (v1.3 NEW red line)**:

The shared lib `scripts/lib/behavior-schema.sh` exposes `redact_cwd()` which collapses `/Users/<self>/foo` → `~/foo` and `/Users/<other>/foo` → `<other>:~/foo` (Linux `/home/<self|other>/...` equivalents; bare `/Users/alice` also collapses to `<alice>:~`). Every reader applies this before emitting records — cwd absolute paths NEVER reach `behavior-raw/`. The `redact-scan.sh` Category 16 also flags any residual `/Users/<name>/` leak in downstream artifacts as a defence-in-depth gate. **The `behavior-raw/` directory is gitignored AND sanitize-ignored — never committed, never bundled into release tarballs.**

**Opt-out**: skip any reader whose tool is not installed (reader exits 0 gracefully). Per-host capacity tuning is reserved for v1.4 cross-tool render — see `docs/cross-tool-roadmap.md`.

## Step 1: Deep scan

Scan CLAUDE.md / AGENTS.md / settings.json / memory/*.md and any agent soul/identity files.

**Fixed locations** (priority order, **Syncthing sync root first**):

1. Any Syncthing sync root identified in Step 0 (highest priority)
2. Dropbox root if present: `~/Library/CloudStorage/Dropbox/` or `~/Dropbox/`
3. iCloud root if present: `~/Library/Mobile Documents/com~apple~CloudDocs/`
4. `~/.claude/` — global settings.json, projects/*/memory/
5. Any custom agent home with its config + workspace files
6. `~/coding/` or similar local dev mirror
7. `~/Desktop/` and `~/Documents/` — shallow (one level) scan for `.claude/` or `CLAUDE.md`

**Dynamic supplement**: hidden projects and any sync-root paths discovered in Step 0 MUST be added.

**Deduplicating the same project across locations**:
- When the same project appears in both a sync root and `~/coding/`, treat the **sync-root copy as authoritative**
- Mark the `~/coding/` copy as "local mirror", don't catalogue separately
- Detect via `.git/config` remote URL, mtime, or file size

**Scan constraints**:
- Max depth: 4 levels
- Exclude: `node_modules` / `.git` / `.venv` / `__pycache__` / `dist` / `build` / `.next`
- Per-directory timeout > 30s -> record to `skipped.log`, skip
- Don't follow symlinks (`find -P`)
- `.md` files > 500 KB -> read first 200 lines only

Per-project record: path, tech stack, language, key config rules, memory contents, session activity.

**MCP server scan** (required for §13 Toolchain — capture ALL installed MCP servers):

```bash
# Primary: global Claude Code config
cat ~/.claude/claude.json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for name,cfg in d.get('mcpServers',{}).items():
    print(f'{name}: {cfg.get(\"command\",\"\")} {\" \".join(cfg.get(\"args\",[]))}'.strip())
" 2>/dev/null

# Secondary: per-project settings
find ~/.claude/projects -maxdepth 3 -name "settings.json" 2>/dev/null \
  | xargs -I{} sh -c 'echo "=== $1 ==="; cat "$1" 2>/dev/null' _ {} \
  | grep -A3 '"mcpServers"' 2>/dev/null || true
```

For each MCP server found, record: **name**, **command/args**, **active scope** (global vs project-local), **purpose** (infer from name if not documented). Include the full list verbatim in §13 Toolchain. Missing MCP entries in §13 = incomplete toolchain config.

## Generation strategy (read before Step 2) — COMMON-first invariant

The artifact ordering below (Step 2 = MAX, Step 2.5 = MIN, Step 3 = COMMON) is **presentation order for readers**, not the internal generation order. Enforce the following order or the subset invariants break:

1. **Internal pass — draft COMMON base**: produce the 10 base rules + §0–§10 of the COMMON `CLAUDE.md` **first**, as the single source of truth. Do not emit files yet.
2. **Step 2 output — emit MAX**: `cat` the COMMON base into the MAX output directory's `rules/01–10-*.md` and CLAUDE.md base chapters verbatim, then append the machine-bound chapters (all machine-bound chapters §11–§16) and any project-specific `rules/11+-*.md`.
3. **Step 2.5 output — emit MIN**: select 7 of COMMON's 10 rules into the MIN output directory, compress each by dropping the "what MIN drops vs COMMON" items, preserve everything in "what MIN keeps", and emit the 8-section CLAUDE.md skeleton.
4. **Step 3 output — flush COMMON**: write the COMMON source-of-truth draft to its own output directory unchanged.

**Preconditions** (assert before each output step; abort and log if violated):

- Before Step 2 (MAX): COMMON base draft must exist in working memory with all 10 rules populated.
- Before Step 2.5 (MIN): COMMON base draft must exist **and** the 10 rules must each have a classified position in MIN (kept / dropped / compressed). Unclassified rules block MIN emission.
- Before Step 3 (COMMON): Step 2 and Step 2.5 must have completed emission so that the post-generation byte-diff (Layer 1 verification) has both sides to compare.

**Subset invariant** (verified in Layer 1): every rule present in MIN must have a byte-identical or superset counterpart in COMMON, and every rule in COMMON must have a byte-identical counterpart in MAX's `rules/01–10-*.md`. Violations block release.

## Step 2: Generate MAX tier

**Machine code + date naming**:

```bash
DATE=$(date +%Y%m%d)

# Machine identifier — use hostname so two machines with identical CPUs get different directories.
# CPU chip is recorded inside run-meta.yaml as `chip:` but NOT used for directory naming.
MACHINE_CODE=$(scutil --get LocalHostName 2>/dev/null | tr '[:upper:]' '[:lower:]')
[ -z "$MACHINE_CODE" ] && MACHINE_CODE=$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')
[ -z "$MACHINE_CODE" ] && MACHINE_CODE="unknown-host"

# Capture CPU separately for run-meta.yaml only (never used in directory name)
CHIP_RAW=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
[ -z "$CHIP_RAW" ] && CHIP_RAW=$(uname -m)

# User override (CCG_MACHINE_CODE still works to force a custom identifier)
MACHINE_CODE="${CCG_MACHINE_CODE:-$MACHINE_CODE}"
PREFIX="${CCG_PREFIX:-CLAUDE-CONF}"

OUT_MAX="${PREFIX}-MAX-${MACHINE_CODE}-${DATE}"
OUT_COMMON="${PREFIX}-COMMON-${DATE}"
OUT_MIN="${PREFIX}-MIN-${DATE}"
```

**Output path** (anti-recursion):

For each tier, write to `<base>/<OUT_NAME>/` where `<OUT_NAME>` is one of `${OUT_MAX}` / `${OUT_COMMON}` / `${OUT_MIN}` (defined in the bash block above). `<base>` is selected by the first matching rule:

1. **If `pwd` is inside the generator's own output tree** (case-insensitive path containing both the `claude` and `config` tokens — see shell check below), `<base>` = `./outputs/`. This prevents the generator from recursively scanning its own output on re-runs.
2. **If Dropbox root exists**, `<base>` = `${DROPBOX_ROOT}/ClaudeConfig/`.
3. **Otherwise**, `<base>` = `~/Desktop/`.

Reference shell check for rule 1 (portable bash, no regex engine required):
```bash
pwd_lc=$(printf '%s' "$PWD" | tr '[:upper:]' '[:lower:]')
case "$pwd_lc" in
  *claude*config*|*config*claude*) INSIDE_SELF=1 ;;
  *) INSIDE_SELF=0 ;;
esac
```

**Conflict handling**: if `<base>/<OUT_NAME>/` already exists, append `-r2`, `-r3`, ... to `<OUT_NAME>` (the full directory name, not the `CCG_PREFIX` env var). Example: `CLAUDE-CONF-MAX-my-macbook-pro-20260421/` already exists → write to `CLAUDE-CONF-MAX-my-macbook-pro-20260421-r2/`.

### Step E1 — `run-meta.yaml` emission (v1.1.0+)

Every generation run MUST write `<base>/<OUT_NAME>/run-meta.yaml` alongside `CLAUDE.md` and `rules/`. This file identifies the contributing host for the multi-machine merge feature (`claudemex merge`).

Required fields (flat YAML, no nesting):

```yaml
# run-meta.yaml — emitted by claudemex generate
host: <scutil --get LocalHostName | tr '[:upper:]' '[:lower:]'>
chip: <sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m>
generator_version: <contents of project VERSION file, e.g. v1.1.0>
tier: <MIN | COMMON | MAX>
generated_at: <UTC ISO 8601, e.g. 2026-05-05T07:35:00Z>
tool: claude
```

Implementation notes:

- `host`: prefer `scutil --get LocalHostName` (macOS); fall back to `hostname -s | tr '[:upper:]' '[:lower:]'` on non-Mac platforms. Empty result → emit `unknown-host`. **This is the primary machine identifier — must match the `MACHINE_CODE` used in the output directory name.**
- `chip`: CPU brand string for informational purposes only. Never used for directory naming (two machines with the same chip would collide).
- `generator_version`: read from the project's root `VERSION` file. If absent, emit `unknown`.
- `tier`: must match the tier you actually wrote (MIN / COMMON / MAX).
- `generated_at`: UTC, ISO 8601 with `Z` suffix.
- `tool`: always `claude` in v1.1.x. Reserved for Phase 2 cross-tool render (Codex / OpenCode renderers consume the same kernel via their own `tool:` value).

This file is read by `scripts/lib/meta-yaml.sh::read_meta_field` during merge; downstream tasks rely on its presence to count contributing hosts. A missing or malformed `run-meta.yaml` causes the generation directory to be skipped during merge with a warning.

### MAX tier artifacts

#### `CLAUDE.md` (16 chapters, write in segments <= 200 lines each)

1. User profile (including usage intensity from Step 0) — with optional Tacit#5 pointer to memory system
2. Communication rules
3. Decision framework (Linus's Three Questions + Karpathy#1 Think Before Coding)
4. Quality gates (authoring/review separation; **Karpathy#4 verification loop lives in §6 Execution — this chapter only references it via a one-line pointer**)
5. Code standards (Karpathy#2 Simplicity + #3 Surgical + Tacit#2 Style Follows Repo + Tacit#3 Convention over Configuration)
6. Execution protocol (memory triggers + Karpathy#4 Goal-Driven + Tacit#1 Read the Room)
7. File/write rules (S-grade protocol, see section below)
8. Security redlines
9. Memory & context management (Tacit#5 Memory is Tacit Knowledge — `HANDOFF.md` / `.memory/` / session-inventory as collective memory)
10. AI collaboration topology (if you use multiple AI assistants)
11. Project catalogue (one entry per project found in scan)
12. Infrastructure & environment (servers, Docker, network if applicable — redact IPs/hostnames per threat model below)
13. Toolchain configuration (installed plugins, MCP servers, model routing)
14. Project-specific rules (Tacit#4 Why > How canonical — full body here for Dev Logs / comments / commit messages)
15. Anti-patterns list (Linus violations + Karpathy 4 violations + Tacit 5 violations specified)
16. Development philosophy & iteration notes (Tacit#4 Why > How pointer only — one-line reference to §14)

#### `rules/` (unified numbering)

- `01-10-*.md`: base universal rules (byte-identical to COMMON tier)
- `11+-*.md`: project-specific rules
- `deploy.sh`: deployment script (spec below)

#### Other artifacts

- `session-inventory.md` — Step 0 output
- `INDEX.md` — directory navigation
- `REPORT.md` — generation summary

## Step 2.5: Generate MIN tier

**Output name**: `${PREFIX}-MIN-${DATE}`

**Position**: Minimum contract for fresh-machine / container / CI scenarios. Stricter than COMMON, contains only what is genuinely unrecoverable for a clean-slate agent.

### Three-tier relationship

```
MIN (minimum, ~580 lines total / ~17K tokens — CLAUDE.md ~160 + rules/ ~410 + INDEX/REPORT ~10)
  subset-of
COMMON (strategic, ~1,311 lines total / ~40K tokens — CLAUDE.md ~480 + rules/ ~820 + scripts)
  subset-of
MAX (machine-bound, ~2,900+ lines total / ~90K+ tokens — COMMON base + project catalogue + infra + project-specific rules)
```

> **Note on numbers**: the "CLAUDE.md" column in the "What this produces" table (above) shows only the CLAUDE.md file's line count, not the full directory. The totals here include CLAUDE.md + rules/ + metadata files.

Every MIN rule has a corresponding or expanded version in COMMON.

### MIN `CLAUDE.md` (~160 lines, Hickey's decision-time skeleton, 9 sections (§0–§8))

- §0 Identity & startup (salutation / start marker / language — all optional, driven by env vars)
- §1 Before — pre-decision (Linus's Three Questions + Karpathy#1 + 1by1 protocol if present — an optional Claude Code skill for structured one-at-a-time decisions)
- §2 Pre-edit — before touching code (Tacit#1 Read the Room + Tacit#5 Memory is Tacit Knowledge)
- §3 During — while coding (Karpathy#2 + #3 + Tacit#2 + #3 + #4)
- §4 After — verification (Karpathy#4 + post-change verification: grep / diff / test)
- §5 Always — hard redlines (secrets / write-size cap / no auto-install / doc-before-config / authoring-review separation)
- §6 User-specific protocols (if any — e.g. recall / emergency-diagnose / compress-memory / reinforce-memory)
- §7 Anti-patterns (user's actual historical footguns + Three-pillar violations)
- §8 Rules index
- Footer: startup convention restated + Karpathy Success Metric quote

### MIN `rules/` (7 files, ~410 lines total)

| # | File | Responsibility | Lines |
|---|------|----------------|-------|
| 01 | `identity.md` | Identity / salutation / start marker / communication bans | ~40 |
| 02 | `decision.md` | Linus's Three Questions + Karpathy#1 + recommendation protocol | ~55 |
| 03 | `execution.md` | Parallelism / segmented output / Karpathy#4 + Tacit#1 / post-change verification | ~70 |
| 04 | `safety.md` | Secrets redline + S-grade write protocol + no auto-install + authoring-review separation | ~55 |
| 05 | `coding.md` | Karpathy#2+#3 + Tacit#2+#3+#4 | ~60 |
| 06 | `memory.md` | User memory protocols + `HANDOFF.md` pointer + Tacit#5 | ~80 |
| 07 | `anti-patterns.md` | User's actual historical footguns + Three-pillar violations | ~50 |

**Numbering note**: MIN uses its own compact numbering (01–07) independent of COMMON's numbering (01–10). They are **not aligned** — see the per-principle mapping in the Embedding Map below. Upgrading MIN → COMMON is **not** a straight file-level replacement and `deploy.sh` does not auto-migrate; use the Embedding Map's "MIN rule file → COMMON rule file" column as your rename guide, then re-run `deploy.sh --force` to install the renamed files. See Embedding Map "MIN rule file" column for canonical per-principle mapping.

> **Numbering semantics**: rule file numbers (`01-`, `02-`, ..., `10-`) are **stable identifiers for cross-tier diffing**, not priority or execution order. `01-identity.md` is not "more important than" `09-anti-patterns.md` — they are orthogonal concerns. For actual priority semantics (what the agent checks first when a conflict surfaces), see the precondition-ordered redlines inside `04-safety.md` / `06-security.md` / `09-anti-patterns.md`.

### What MIN drops vs COMMON

- Generic software-engineering anti-patterns (deep nesting / large functions / file-size heuristics) — common knowledge
- Framework preferences (DDD / TDD specifics) — not universally applicable
- Multi-AI collaboration details — compressed to a one-line pointer
- Standalone "rules index" chapter — MIN lists them inline in §8
- Software-engineering-common anti-patterns already in any competent agent's prior

### What MIN keeps (details matter — each entry carries its "because")

Each item below is retained **with** its reason, because Polanyi's tacit-knowledge test says a rule without its grounding is a string that will be dropped on the next compression pass.

- **Secrets redline** — *because* model drift silently erodes even OWASP-common assumptions; explicit re-assertion is the only defense that survives weight updates.
- **Full S-grade write protocol** (size cap / edit-read-first / edit-fail-twice-then-write / no blind sed) — *because* every clause traces to a real incident category, not a hypothetical; removing any clause brings back a known failure mode.
- **Post-change verification** (grep + diff + curl double-check) — *because* silent success is the most expensive failure mode — diffs lie when your eyes are tired.
- **Documentation-before-config** (never write config field names from memory) — *because* a 30-second docs lookup costs strictly less than debugging a guessed field name, and the model cannot know which fields it has hallucinated.
- **Authoring / review separation** — *because* same-context self-review is a known confabulation trap (see Phase 2 disclaimer above).
- **Full 1by1 protocol format** (if the user has it — an optional Claude Code skill for structured one-at-a-time decisions) — *because* compressing a decision protocol drops its mechanical value; either the full format or drop it entirely.
- **User-specific memory protocols** (recall / emergency / compress / reinforce, if any) — *because* these are the only bridge a fresh-machine agent has to prior continuity.

### Decision rule for drops vs keeps — necessity matrix

Classify each candidate entry along two axes:

| | **Recoverable from code / standard priors alone** | **NOT recoverable without explicit rule** |
|---|-----|-----|
| **Common prior** (any competent agent already knows this) | **DROP** — MIN is not a digest of CS 101 | **KEEP** — anchor against model drift (e.g. secrets redline) |
| **User-specific / project-specific** | **DROP** — carried by `HANDOFF.md` / `.memory/` (see C.5) | **KEEP** — this is MIN's load-bearing content (e.g. user memory protocols) |

**Tie-breaker**: if removing an entry would leave a **recoverability hole** (user steps on a known trap, or agent confabulates), keep it even if it duplicates common knowledge. If removing it leaves no observable hole, drop it.

**Default to DROP when uncertain**: a MIN that keeps too much defeats its own purpose. MIN exists to load fast, cost few tokens, and frame fresh-machine / container / CI scenarios — not to be a comprehensive tutorial.

## Step 3: Generate COMMON tier

> **Execution note**: see "Generation strategy" above — Step 3 **flushes the internal COMMON draft** produced before Step 2. The draft is the single source of truth from which Step 2 (MAX) and Step 2.5 (MIN) were already derived. Step 3 is not a fresh independent generation; its output must be byte-identical to the draft that seeded Step 2's base chapters (verified by Layer 1 Consistency).

**Output name**: `${PREFIX}-COMMON-${DATE}`

**Two-tier relationship** (COMMON <-> MAX):
- COMMON = single source of truth (base 10 rules)
- MAX's "user profile / decision framework / execution protocol" chapters = **byte-identical copies** of COMMON's corresponding chapters (post-generation diff verification)
- MAX only **appends** project catalogue / infrastructure / project-specific rules beyond COMMON

### COMMON `CLAUDE.md` (~480 lines strategic, 11 chapters)

§0 Core identity / §1 Decision framework (+ Linus's Three + Karpathy#1) / §2 Execution discipline (+ Karpathy#4 + Tacit#1) / §3 Quality standards / §4 File & write safety / §5 Security principles / §6 Multi-AI collaboration / §7 Coding philosophy (+ Karpathy#2 + #3 + Tacit#2 + #3 + #4) / §8 Memory & context (+ Tacit#5) / §9 Anti-patterns (+ Linus violations + Karpathy 4 + Tacit 5) / §10 Rules index

### COMMON `rules/` (10 files + deploy.sh)

`01-identity` / `02-execution` (memory triggers + Karpathy#4 + Tacit#1) / `03-quality` / `04-decision` (Linus's Three + Karpathy#1) / `05-file-safety` (S-grade) / `06-security` / `07-memory` (+ Tacit#5) / `08-coding` (Karpathy#2 + #3 + Tacit#2 + #3 + #4) / `09-anti-patterns` (Linus + Karpathy + Tacit trio) / `10-plugins-skills`

## Review system — Two phases (MIN tier)

MIN compression carries risk (dropping a critical contract, or keeping too much and losing the MIN benefit). The review system has **two sequential phases**, not parallel lanes: Phase 1 is the executable gate that must pass; Phase 2 is an optional self-review discipline that runs **before** Phase 1 to raise the chance Phase 1 passes on first try.

### Phase 1 — Anchor-phrase & structural verification (MANDATORY, blocking)

This is the **only actual release gate**. Purely mechanical, CI-runnable, independent of any persona reasoning.

See the "Verification (post-generation)" section below for exact checks. Bottom line: if any mandatory anchor phrase or structural assertion is missing, generation is blocked, revise, retry.

### Phase 2 — Three-persona review framing (OPTIONAL, runs before Phase 1)

A thinking framework for pre-Phase-1 self-review. **Not a gate.** The three personas are lenses, not independent reviewers — running them inside a single model session is a **discipline**, not an independence check. Skipping Phase 2 is fine; Phase 1 is the only blocking requirement.

> **Honest disclaimer** (must appear verbatim in the generator output): "Self-review using these three personas is a thinking discipline, not an independent audit. Running all three inside a single model session cannot produce true independence no matter how the prompts differ. For genuine independence, dispatch each persona to a different model instance or human collaborator. Phase 1 is what actually gates release; Phase 2 only raises the odds that Phase 1 passes on first try."

#### The three lenses

| Persona | Domain | Principle | Self-review axis |
|---------|--------|-----------|------------------|
| **Linus Torvalds** | Minimum / Good Taste | "Talk is cheap. Show me the code." / eliminate special cases | Is each line a rule or mere documentation? Would removing it cause observable failure? |
| **Rich Hickey** | Philosophy Logical | *Simple Made Easy* / Simple ≠ Easy / complecting vs composing | Are the rules orthogonal? Are they organised by decision-time rather than topic? |
| **Michael Polanyi** | Tacit Knowledge | "We know more than we can tell" / subsidiary vs focal awareness | Does MIN capture the full tacit contract? Are pointers to tacit-knowledge carriers (`HANDOFF.md`, `.memory/`) preserved? Passes the recoverability test? |

#### Framing usage (optional)

**Trigger window**: Phase 2 runs **after the MIN draft is prepared in working memory and before the MIN files are written to disk** (i.e. between the internal compression pass and Step 2.5 output emission). If Phase 2 is skipped, proceed directly to Step 2.5 emission and then to Phase 1 gate.

1. Generate MIN draft (in working memory, not yet written to disk)
2. Apply each persona as a self-review checklist; optionally produce `MIN-REVIEW-linus.md` / `MIN-REVIEW-hickey.md` / `MIN-REVIEW-polanyi.md`
3. Merge critiques if produced; common ground adopted directly
4. Revise the draft, then proceed to Step 2.5 emission, then run Phase 1 until Phase 1 passes (re-iterate if Phase 1 fails)

#### When to upgrade to real independent review

When this project has **independent external review capacity** — unsolicited PRs from non-author contributors, formal adopters with their own security/architecture review teams, or any reviewer who is not the original prompt author running the same model — upgrade Phase 2 from "self-review framing" to genuine independence: each persona dispatched to a distinct model instance (Claude / GPT-class / Gemini-class, ideally different vendors to avoid shared training prior) or a distinct human reviewer. At that point, the three reviews become a proper external audit and can justly be called an "Agent Teams review."

> **Why no hard threshold**: a specific number (e.g. "100 stars") is arbitrary and doesn't track the actual signal — which is whether there's someone outside the author's own session running the review. One high-signal external reviewer beats ten same-model self-passes.

## Three mandatory principle groups (all three tiers MUST embed)

**Trinity**: Linus's Three Questions (should-we-do-it) + Karpathy's 4 (how-to-approach-it) + Tacit Knowledge 5 (read-the-room). Missing any category blocks generation. The order is **not priority**; any violation is a defect.

---

### Group A — Linus's Three Questions (answer before every proposal)

Source: Linus Torvalds's well-known decision heuristic, widely adopted across open-source communities.
Purpose: decision layer — "should this even be done, is there a simpler path, what does it break?"

Three questions (must appear verbatim in each tier's decision-framework chapter):

1. **Is it a real problem?** — reject over-engineering and imagined needs
2. **Is there a simpler way?** — seek the most direct, least-code solution
3. **What does it break?** — ensure backward compatibility and system stability

Required behavior:
- Answer all three **before** proposing a solution (write them out in chat)
- Just listing options without recommending = violation of Linus's Three
- When multiple approaches exist, pick one based on the three answers and explain why

Complementarity with Karpathy#1:
- **Linus** governs "should-we-do-it, should-we-redo-it, will-it-break-something"
- **Karpathy#1** governs "have we surfaced assumptions and confusions before starting"
- Both must pass before executing

---

### Group B — Karpathy's 4 Rules (LLM coding behavior)

Source: Andrej Karpathy's recommended LLM coding behavior rules (publicly available as a reference CLAUDE.md on GitHub).
Tradeoff declaration (must appear verbatim in each tier's CLAUDE.md):

> "These guidelines bias toward caution over speed. For trivial tasks, use judgment."

#### B.1 Think Before Coding (in the decision-framework chapter)

> **Don't assume. Don't hide confusion. Surface tradeoffs.**

Action items:
- State assumptions explicitly before starting; if unsure, ask
- When multiple interpretations exist, list them all — don't pick silently
- When a simpler approach exists, say so; push back when warranted
- When something is unclear, stop, name what's confusing, ask

#### B.2 Simplicity First (in the coding-standards chapter)

> **Minimum code that solves the problem. Nothing speculative.**

Action items:
- No features beyond what was asked
- No abstractions for single-use code
- No "flexibility" or "configurability" that wasn't requested
- No error handling for impossible scenarios
- If you write 200 lines and it could be 50, rewrite it
- Ask: "Would a senior engineer say this is overcomplicated?"

#### B.3 Surgical Changes (in the coding-standards chapter)

> **Touch only what you must. Clean up only your own mess.**

Action items:
- Don't "improve" adjacent code, comments, or formatting
- Don't refactor things that aren't broken
- Match existing code style, even if you'd do it differently
- If you notice unrelated dead code, mention it — don't delete it
- Orphans created by your changes (imports/vars/functions) — you clean
- Pre-existing dead code — leave it unless asked
- **Test**: every changed line must trace directly to the user's request

#### B.4 Goal-Driven Execution (canonical: execution-protocol; quality-gates references only)

> **Define success criteria. Loop until verified.**

Action items:
- Transform tasks into **verifiable goals**:
  - "Add validation" -> "Write tests for invalid inputs, then make them pass"
  - "Fix the bug" -> "Write a test that reproduces it, then make it pass"
  - "Refactor X" -> "Ensure tests pass before and after"
- For multi-step tasks, state a brief plan:
  ```
  1. [Step] -> verify: [check]
  2. [Step] -> verify: [check]
  ```
- Strong success criteria let you loop independently; weak criteria ("make it work") require constant clarification

> **Canonical location rule** (Hickey composing principle): this rule's full body lives **only** in the execution-protocol chapter (`02-execution.md` / MAX §6 / COMMON §2). Quality-gates chapter (`03-quality.md` / MAX §4) contains a **pointer only**, of the form: `> Verification loop: see 02-execution.md — Karpathy#4 Goal-Driven Execution`. Duplicating the full body across two chapters is complecting and must not occur.

---

### Group C — Tacit Knowledge (pre-action gate)

Core thesis: **not understanding the scene = not understanding the request**. Unwritten conventions and "any senior would immediately spot this is wrong" judgements form the real spine of a project.
Violating tacit knowledge = technically correct, contextually wrong — harder to detect than buggy code.

Applies to: all generated / modified code, config, documentation. Tacit Knowledge is a **pre-action** gate, not a post-hoc review.

#### C.1 Read the Room (before touching anything)

Required survey before action (missing any item = violation):
- Read the full target file (not just lines-around-the-edit)
- Read at least 20 lines of surrounding context
- Read the most recent entry in `HANDOFF.md` (project handoff doc, if present)
- Read `.memory/context.md` and `.memory/progress.md` (if present)
- Read `session-inventory.md` (Step 0 output) for active-project profile and recent usage patterns (if present — check freshness per C.5 table)
- Review relevant session history
- Grep for similar implementations (same function name / pattern)

**Test**: can you explain in one sentence **why** the code is written this way? If not, the survey is incomplete.

#### C.2 Style Follows Repo

**Repo style > personal preference > community "best practice"**:
- snake_case vs camelCase -> follow the repo
- type-hint usage / indentation / error-handling idiom -> follow the repo
- 2-space vs 4-space -> follow the repo (even if PEP 8 says 4)
- `if err != nil` -> keep it, don't "modernise" to `errors.Is`
- Builds on Karpathy#3 Surgical Changes, one step deeper: **not only don't change adjacent code, the new code you write must also match repo style**

**Test**: drop your new code into `git blame`; if it's indistinguishable from AI or a new hire, good.

#### C.3 Convention over Configuration

**Existing patterns in the repo** (even if unwritten) are strong rules:
- All error paths `return errors.New` rather than `panic` -> you also `return errors.New`
- All logs go through `logger.Info` rather than `fmt.Println` -> you too
- All config lives under `config/` rather than inline -> you put yours there too
- Before violating, explicitly state in chat / Dev Log: "I know the project uses X, but I need Y here because [reason]"

**Test**: violating an existing convention without declaring it = automatic fail.

#### C.4 Why > How (for comments, Dev Logs, commit messages)

**Code says How, comments say Why**:
- How (what was done) — code says it; reading the code suffices
- Why (why this, why not that, what pitfall, what constraint) — code doesn't say it
- Comments / PR descriptions / Dev Logs / commit messages — prioritise Why
- "Fix bug" ❌ / "Because the service user couldn't read the 600-permission config, third instance of this class of issue" ✅

**Test**: if deleting the comment wouldn't harm a future reader's understanding, don't write it; if deleting would make them step on the same trap, it must be written.

#### C.5 Memory is Tacit Knowledge

**Carriers of tacit knowledge** (read before acting, else it counts as "acting without understanding"):
- `HANDOFF.md` — project-level handoff doc (most recent Dev Log)
- `.memory/context.md` / `progress.md` / `INDEX.md` — cross-device portable memory
- `.memory/session-*.md` — historical session decision trails
- `~/.claude/projects/<encoded-path>/memory/` — Claude native memory
- `session-inventory.md` (Step 0 output) — active-project profile
- Any agent soul/identity file relevant to the scenario

**Anti-examples**: bypassing `HANDOFF.md` and editing code directly / ignoring `context.md` and redoing last time's work / hitting a known pitfall without checking history.

**Test**: after completing the task, would the user say "we did this last time" or "we've hit this pitfall before"? If yes, C.5 was violated.

**Freshness thresholds** (anti-decay mechanism — carriers older than these should be treated with suspicion, not as ground truth):

| Carrier | Fresh | Stale (verify against code) | Archived (likely dead) |
|---------|-------|----------------------------|------------------------|
| `HANDOFF.md` most recent Dev Log | ≤ 24h | 1–7 days | > 7 days |
| `.memory/context.md` / `progress.md` | ≤ 7 days | 7–30 days | > 30 days |
| `.memory/session-*.md` | ≤ 30 days | 30–90 days | > 90 days |
| `session-inventory.md` (Step 0 output) | ≤ 7 days | 7–30 days | > 30 days |

**Decay protocol**:
- **Fresh** — trust as current context; act on named files / functions / flags without re-verification
- **Stale** — read them, but verify any named file / function / flag still exists in the live tree before acting on it
- **Archived** — treat as historical context only; don't propose actions based on them without re-reading current code first
- **All relevant carriers archived** (fresh-machine / container / CI scenario) — declare in chat: "no tacit context available, proceeding from code-only survey" and fall back to pure Read-the-Room (C.1) before acting

Each MIN `06-memory.md` / COMMON `07-memory.md` / MAX §9 must include the table above verbatim and name the `mtime`-based check as the operational definition of freshness.

### Embedding map (generator reference)

| Principle | MAX chapter | COMMON chapter | COMMON rule file | MIN chapter | MIN rule file |
|-----------|-------------|----------------|------------------|-------------|---------------|
| **A** Linus's Three | §3 Decision framework | §1 Decision framework | `04-decision.md` | §1 Before | `02-decision.md` |
| **B.1** Think Before Coding | §3 Decision framework | §1 Decision framework | `04-decision.md` | §1 Before | `02-decision.md` |
| **B.2** Simplicity First | §5 Code standards | §7 Coding philosophy | `08-coding.md` | §3 During | `05-coding.md` |
| **B.3** Surgical Changes | §5 Code standards | §7 Coding philosophy | `08-coding.md` | §3 During | `05-coding.md` |
| **B.4** Goal-Driven Execution | §6 Execution (canonical) + §4 Quality gates (pointer only) | §2 Execution discipline | `02-execution.md` | §4 After (canonical) | `03-execution.md` |
| **C.1** Read the Room | §6 Execution | §2 Execution discipline | `02-execution.md` | §2 Pre-edit | `03-execution.md` |
| **C.2** Style Follows Repo | §5 Code standards | §7 Coding philosophy | `08-coding.md` | §3 During | `05-coding.md` |
| **C.3** Convention over Configuration | §5 Code standards | §7 Coding philosophy | `08-coding.md` | §3 During | `05-coding.md` |
| **C.4** Why > How | §14 Project-specific (canonical) / §16 pointer-only | §7 Coding philosophy | `08-coding.md` | §3 During | `05-coding.md` |
| **C.5** Memory is Tacit Knowledge | §1 User profile + §9 Memory | §8 Memory & context | `07-memory.md` | §2 Pre-edit | `06-memory.md` |
| All violations | §15 Anti-patterns | §9 Anti-patterns | `09-anti-patterns.md` | §7 Anti-patterns | `07-anti-patterns.md` |

> **MIN subset invariant**: every MIN cell above must have a non-empty counterpart in the COMMON / MAX cells of the same row. Any row with a MIN assignment but no COMMON assignment is a subset violation — fix by either upgrading the principle to COMMON or dropping it from MIN.

### Canonical location rules (Hickey composing, no duplication)

A principle with multiple chapter entries in the table above must have **one canonical location** (full body) and **pointer-only** entries everywhere else. Duplicating the full body across chapters is complecting and blocked.

| Principle | Canonical location (full body) | Pointer-only locations (one-line reference) |
|-----------|-------------------------------|---------------------------------------------|
| **B.4** Goal-Driven Execution | Execution chapter (MAX §6 / COMMON §2 / `02-execution.md`) | Quality gates (MAX §4 / `03-quality.md`) |
| **C.4** Why > How | Project-specific rules (MAX §14 for Dev Logs / comments / commit messages; COMMON §7 `08-coding.md`; MIN `05-coding.md`) | Iteration notes (MAX §16 — one-line reference only) |
| **C.5** Memory is Tacit Knowledge | Memory chapter (MAX §9 / COMMON §8 / `07-memory.md` / MIN `06-memory.md`) | User profile (MAX §1) |

**Scope note**: this table only applies **within** a single tier when the same principle would otherwise appear in full form in two or more chapters of that tier. Cross-tier placement (where a principle naturally sits in each tier) is governed by the Embedding Map above — canonical/pointer split is a per-tier concern.

**Pointer format** (verbatim, so Layer 2 structural gate can detect it):

```
> Canonical: see <chapter> — <principle name>. This chapter references it only.
```

All other principles in the Embedding Map (A, B.1, B.2, B.3, C.1, C.2, C.3) have a single natural chapter per tier — no pointer needed. If a future revision ever places one of them in two chapters, add it to this table first.

### Writing requirements

1. Each tier's CLAUDE.md opening must declare: "This configuration combines Linus's Three Questions + Karpathy's LLM coding rules + Tacit Knowledge — these guidelines bias toward caution over speed."
2. All **English original phrases** (Karpathy 4, Tacit 5 key terms: `Read the Room` / `Style Follows Repo` / `Convention over Configuration` / `Why > How` / `Memory is Tacit Knowledge`) must be preserved bilingually if the user's language isn't English — English is the edge.
3. When existing rules conflict, **these principles take precedence**, with a note on the superseded rule: "_(superseded by Linus-A / Karpathy#N / Tacit#N)_"
4. Anti-patterns list must auto-append these violation forms:
   - Linus: proposing without answering Three / listing options without recommending / multi-option without reasoning
   - Karpathy #1–#4: corresponding violations per rule
   - Tacit #1–#5: acting without reading / personal style overriding repo style / violating convention without declaring / comments only saying How / ignoring HANDOFF and `.memory/`
5. **Success metric footnote** (each tier's CLAUDE.md footer, verbatim):
   > "These guidelines are working if: fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes."
6. **Optional salutation + start-marker section**: if `CCG_SALUTATION` or `CCG_START_MARKER` is set, append a trailing chapter "Personal salutation & start marker" describing them and cite assertion in `01-identity.md`. If neither env var is set, omit the chapter entirely.

---

## Deploy script spec (`deploy.sh`)

Must support:
- `--force`: accept flag explicitly; current behavior already overwrites existing files
- **Backup**: before overwrite, copy `CLAUDE.md` to `CLAUDE.md.bak` in the target directory
- Usage: `bash deploy.sh <MIN|COMMON|MAX> <target-dir> [--base <outputs-path>] [--force]`

Deploy targets:
- Base `01-10` (COMMON or MAX) -> `~/.claude/rules/`
- Base `01-07` (MIN) -> `~/.claude/rules/` (upgrade-in-place: existing COMMON rules at higher numbers are left untouched; `deploy.sh` detects tier by checking the `rules/` file count of the source directory)
- Project `11+` (MAX only) -> each project's `.claude/rules/`

## Execution constraints

### Write constraints
- Each single write **<= 200 lines**
- Before any `edit`, `read` the file first; after 2 `edit` failures switch to `write`
- Complete the full scan (Step 0 + Step 1) before starting generation

### Credential / secret redaction list (MAX tier mandatory)

**Threat model configurable**. Default (conservative): redact every pattern below; for personal / trusted-device scenarios users may relax per their judgment.

| Pattern (always redact by default) | Replace with |
|-----------|--------------|
| API keys: `sk-[A-Za-z0-9]{20,}` / `sk-ant-*` / `ghp_*` / `AIza*` / `hf_*` | `<API_KEY>` |
| Plaintext passwords: `password\s*[:=]\s*\S+` / `passwd\s*[:=]\s*\S+` / `bot_token\s*[:=]\s*\S+` | `<PASSWORD>` |
| SSH private keys `-----BEGIN` ... `-----END` | **skip entire block** |
| Third-party webhooks / app secrets / encrypt keys | `<WEBHOOK>` / `<APP_SECRET>` / `<ENCRYPT_KEY>` |
| OAuth tokens (Dropbox / GitHub / etc.) | `<OAUTH_TOKEN>` |
| Server IP addresses (IPv4 + IPv6) | `<SERVER_IP>` unless user opts in to keep them |
| Hostnames / device names | `<HOST>` unless user opts in |
| Personal email / phone | `<EMAIL>` / `<PHONE>` |

**User opt-out** (explicit env var or in-session confirmation required):
- Keep server IPs in plaintext (if firewall + key-only auth means IP leaks aren't a concern for the user)
- Keep internal / WG IPs (not publicly routable)
- Keep hostnames (no reuse value outside the machine)

**COMMON tier**: strips project names / personal names / specific ops commands, but **allows** placeholders and illustrative IPs/emails (as examples, not real values).

**MIN tier**: inherits COMMON's redaction posture. MIN rarely contains machine-specific content, but if user-specific memory protocols (recall / compress / reinforce) or anti-pattern examples embed credentials, hostnames, or personal identifiers, they must be redacted per the table above before writing to disk.

### Error handling
- Non-existent / unreadable directories -> `skipped.log`, continue
- Per-directory timeout > 30s -> skip, record
- Corrupt `.jsonl` / `.md` -> skip that file only

### Verification (post-generation) — three layers, increasing specificity

All three layers run against each tier's generated artifacts. Layers 1–2 are **mandatory blocking**; Layer 3 is **advisory warning**.

#### Layer 1 — Consistency + Security (MANDATORY, blocking)

1. **Consistency**: section-by-section diff between MAX's base chapters and COMMON — must be byte-identical
2. **Security**: run credential redaction grep; any hit blocks release

#### Layer 2 — Structural gate (MANDATORY, blocking) — Polanyi-approved

Instead of string grep, verify that **structural pointers** to tacit-knowledge carriers are present as **live references**:

- **Live `HANDOFF.md` reference**: the generated `06-memory.md` (or equivalent memory rule) must contain a reference to `HANDOFF.md` that is **not inside a fenced code block example**. Pointer must be operational (describes reading/writing the file), not illustrative.
- **`.memory/` entry-point**: the generated memory rule must enumerate at least three sub-elements of `.memory/` (e.g. `context.md`, `progress.md`, `INDEX.md` or `session-*.md`).
- **User-protocol trigger section**: the generated memory rule must contain a section describing at least one user-specific protocol trigger (e.g. `recall` / emergency diagnose / memory compression). If none configured via env vars, a placeholder section is acceptable but must exist as an empty template header.

Reference implementation: the canonical generator repository ships a `structural-gate.sh` script under `Release/`. When running this prompt standalone (without cloning the repo), the agent implements the three checks inline via `grep` / `awk` / `test` against the generated artifacts and reports pass/fail in `REPORT.md`.

#### Layer 3 — Anchor-phrase check (tiered: mandatory for quotations, advisory for self-named concepts)

**Mandatory (blocking)** — third-party quotations must be preserved verbatim for citation accuracy:

- Karpathy 4 English originals (all four):
  - `Don't assume. Don't hide confusion`
  - `Minimum code that solves the problem`
  - `Touch only what you must`
  - `Define success criteria. Loop until verified`
- Footer grep: `fewer unnecessary changes in diffs` (Karpathy Success Metric)

**Advisory (warning, non-blocking)** — self-named concepts whose literal phrasing is less load-bearing than their structural embodiment (already checked in Layer 2):

- Linus's Three Questions phrasing
- Tacit 5 key phrases (`Read the Room` / `Style Follows Repo` / `Convention over Configuration` / `Why > How` / `Memory is Tacit Knowledge`)

Missing advisory phrases emit a warning but do **not** block release. Rationale: the concepts are verified by Layer 2 structural checks, not by string matching. Polanyi's critique: requiring a literal phrase is exactly the token-substituted-for-concept move that tacit knowledge resists.

**Optional (if env vars set)**: salutation / start-marker hit in `01-identity.md`.

### `REPORT.md` required contents

- Scan coverage: N projects / M memory files / K sessions
- Session profile: active hours / top 5 projects / hidden projects
- Sync-root list + device ID distribution (cross-device collaboration profile)
- Same-project dedup report (sync-root vs local mirror comparison)
- Collaboration hotspots (`.stversions/` high-frequency files / `.sync-conflict-*` distribution)
- Skip log summary
- Credential redaction hit count
- Consistency diff result (MAX base chapters vs COMMON)
- **Three-layer verification audit**:
  - Layer 1: consistency + security outcome
  - Layer 2: structural gate results (HANDOFF reference / `.memory/` enumeration / protocol trigger section)
  - Layer 3: mandatory Karpathy quotation hits + Success Metric footer; advisory Linus-3 / Tacit-5 hit counts
  - (Optional) salutation / start-marker confirmation if env vars set

=== COPY TO HERE ===
````

---

## Incremental update mode (`--mode=patch`)

The default mode does a **full scan + full generation** — suitable for first-time setup or a major configuration overhaul. For routine two-week retrospectives or minor project additions, use **patch mode** to diff the current config against recent session signals and emit only what changed.

### When to use patch mode

| Scenario | Use |
|----------|-----|
| First machine setup or complete refresh | Default (full) mode |
| Bi-weekly retrospective (`claude-me` habit) | **Patch mode** |
| Added 1–2 new projects since last generation | Patch mode |
| Changed a core principle (e.g. new salutation, new anti-pattern) | Patch mode |
| Switching machines | Default mode (full scan of new machine) |

### How to trigger patch mode

Add `--mode=patch` as the first line of your prompt paste, followed by the path to your existing config:

```
--mode=patch TARGET=~/Desktop/CLAUDE-CONF-COMMON-20260401/
```

Or set the env var before pasting:

```bash
export CCG_MODE=patch
export CCG_PATCH_TARGET=~/Desktop/CLAUDE-CONF-COMMON-20260401/
```

### What patch mode does

**Step P0 — Diff signals** (fast, ~30–60s):
1. Re-run Step 0 session scan (metadata only, no deep project scan)
2. Compare: new sessions since `TARGET`'s last-modified date
3. Identify: new projects not in `TARGET/CLAUDE.md §11`, changed memory files, changed `settings.json`
4. **Correction signal extraction** — scan JSONL session files modified in the last 30 days for behavioral corrections:
   - Search for high-frequency correction markers across all recent `.jsonl` files:
     ```bash
     find ~/.claude/projects -type f -name "*.jsonl" -mtime -30 \
       | xargs grep -hiE \
         '"(content|text)"[[:space:]]*:[[:space:]]*"[^"]{0,200}(don'\''t|do not|stop|undo|revert|wrong|no,|不要|别|错了|改回)[^"]{0,200}"' \
         2>/dev/null \
       | grep -oiE '(don'\''t [^"]{5,60}|do not [^"]{5,60}|stop [^"]{5,60}|不要[^"]{3,30}|别[^"]{3,30})' \
       | sort | uniq -c | sort -rn | head -20
     ```
   - Any phrase appearing **≥ 3 times** across sessions is a `[CORRECTION SIGNAL]` candidate
   - Group semantically similar corrections (e.g. "don't summarize", "stop summarizing", "no summary" → one candidate)
   - Output: top-5 correction signals with frequency count and representative example quote

**Step P1 — Classify changes** (emit one-line summary per changed area):
- `[NEW PROJECT]` — project found in scan not in existing §11
- `[NEW PATTERN]` — anti-pattern or rule detected from correction signals (Step P0.4) not yet in anti-patterns list
- `[CORRECTION SIGNAL]` — high-frequency user correction (≥3 occurrences) — present to user for confirmation before adding to config
- `[STALE ENTRY]` — project or rule in existing config with zero recent session activity (>30 days)
- `[DRIFT]` — memory file content diverges from corresponding config section

**Correction signal handling protocol**:
- Present each `[CORRECTION SIGNAL]` as a proposed anti-pattern addition: show frequency, example quote, proposed rule wording
- User confirms (yes/no/edit) before it enters the config — never auto-add
- Confirmed signals go into `rules/anti-patterns.md` as a new entry under `## Learned from sessions`
- Rejected signals are logged in `PATCH-REPORT.md` under `## Declined corrections` (for future reference)

**Step P2 — Emit minimal patch** (only changed sections, not full file rewrites):

Output to `<TARGET>-patch-<DATE>/`:
- `CLAUDE.md.patch` — unified diff of §11 (new projects added, stale projects flagged with `# STALE: last active YYYY-MM-DD`)
- `rules/` — only the rule files that changed (not all 10)
- `PATCH-REPORT.md` — what changed / what was skipped / what needs manual review

**Step P3 — Append to `patch_history.jsonl`** (in the TARGET directory, one line per patch run):

```json
{"date":"YYYY-MM-DD","mode":"patch","corrections_found":N,"corrections_accepted":N,"drift_score":N,"anchors_all_present":true,"note":"optional free-text"}
```

Fields:
- `corrections_found` — count of `[CORRECTION SIGNAL]` items found in P0.4
- `corrections_accepted` — count the user confirmed (yes) vs total
- `drift_score` — count of `[DRIFT]` items from P0 (0 = clean, >5 = regen recommended)
- `anchors_all_present` — boolean: did the Layer 3 anchor-phrase check pass?

If `patch_history.jsonl` has ≥ 3 entries with the **same correction category** repeated, flag it:
> ⚠ `[ESCALATION]` — "stop summarizing" has appeared in 3 consecutive patch runs. This rule is not being retained. Consider moving it from `anti-patterns.md` into a `[NEVER DO]` block in the main `CLAUDE.md §1` instead.

**Patch mode invariants**:
- Never overwrites the TARGET directory — always writes to a new `<TARGET>-patch-<DATE>/` directory
- Only emits files that have substantive changes (>3 lines diff); cosmetic whitespace diffs are suppressed
- If `[DRIFT]` items exceed 5, recommend full-mode re-generation instead of patching
- Runs the same Layer 1 redaction gate as full mode before writing any output

### Bi-weekly retrospective habit ("ClaudeMeX" rhythm)

Recommended schedule: **every two weeks**, paste the patch-mode prompt to capture:
- New projects you've started
- Patterns Claude has corrected you on (behavioral drift in your CLAUDE.md rules)
- Stale projects to archive or remove
- Memory files that have grown but aren't reflected in your config

The `PATCH-REPORT.md` is intentionally brief — it's a decision surface, not a log. Review it, apply the diffs you agree with, discard the rest.

---

## Contributing

This generator is community-maintained. If you discover a blind spot or optimisation, open a PR to update the changelog and the corresponding chapter.

Suggested roadmap:
- [ ] Language packs (Chinese / Japanese / German / Spanish source text for Three Questions + Tacit 5)
- [ ] Automated `deploy.sh` unit tests
- [ ] Hook for CI auto-regeneration on changelog-bump
- [ ] Benchmark: average token cost across generated tiers on reference machines
- [ ] Patch mode: automated bi-weekly cron trigger (launchd / systemd timer)

## Acknowledgements

- **Linus Torvalds** for the "good taste" heuristic that became the Three Questions
- **Andrej Karpathy** for the publicly shared LLM coding behavior rules
- **Rich Hickey** for *Simple Made Easy* and the simple-vs-easy distinction
- **Michael Polanyi** for *Personal Knowledge* (1958) and the tacit knowledge framework
- Countless Claude Code users whose field reports shape this generator's iterations

## License

MIT — see top of file.

