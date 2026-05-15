#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
workdir=$(mktemp -d); fake_home=$(mktemp -d)
trap 'rm -rf "$workdir" "$fake_home"' EXIT

# === Step 1: Build 4 synthetic CLI fixtures ===

# Claude
mkdir -p "$workdir/claude-fixture"
cat > "$workdir/claude-fixture/sample.jsonl" <<JSON
{"timestamp":"2026-05-04T16:19:17Z","role":"user","content":"不要 sed 盲改文件","sessionId":"s1","cwd":"/Users/niu/c"}
JSON
touch -t 202605110000 "$workdir/claude-fixture/sample.jsonl"

# Codex
mkdir -p "$workdir/codex-fixture/sessions/2026/05/04"
cat > "$workdir/codex-fixture/sessions/2026/05/04/rollout-001.jsonl" <<JSON
{"timestamp":"2026-05-04T16:20:00Z","type":"session_meta","payload":{"id":"sid-001","timestamp":"2026-05-04T16:20:00Z","cwd":"/Users/niu/c","originator":"CodexCli"}}
{"timestamp":"2026-05-04T16:20:01Z","type":"event_msg","payload":{"type":"user_input","text":"必须 read 后再 edit"}}
JSON
touch -t 202605110000 "$workdir/codex-fixture/sessions/2026/05/04/rollout-001.jsonl"

# Gemini (synthetic history)
mkdir -p "$workdir/gemini-fixture/history/niu"
cat > "$workdir/gemini-fixture/history/niu/conv-001.json" <<JSON
[{"ts":"2026-05-04T16:21:00Z","text":"don't bypass validation"}]
JSON
touch -t 202605110000 "$workdir/gemini-fixture/history/niu/conv-001.json"

# OpenCode (sqlite3 synthetic db)
python3 - <<PY
import sqlite3, json, pathlib
p = pathlib.Path("$workdir/opencode-fixture/opencode.db")
p.parent.mkdir(parents=True, exist_ok=True)
c = sqlite3.connect(p)
c.executescript("""
CREATE TABLE session (id TEXT PRIMARY KEY, time_created INTEGER);
CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
""")
c.execute("INSERT INTO session VALUES (?,?)", ("s1", 1777911632))
c.execute("INSERT INTO message VALUES (?,?,?,?,?)",
          ("m1","s1",1777911632,1777911632,
           json.dumps({"role":"user","content":"always verify after deploy","cwd":"/Users/niu/c"})))
c.commit(); c.close()
PY
touch -t 202605110000 "$workdir/opencode-fixture/opencode.db"

# === Step 2: Run all 4 readers into the same $OUT_DIR (behavior-raw/) ===
raw="$workdir/behavior-raw"
mkdir -p "$raw"
CLAUDE_HOME="$workdir/claude-fixture"      bash "$proj/scripts/behavior-scan-claude.sh"   --out-dir="$raw" 2>/dev/null
CODEX_HOME="$workdir/codex-fixture"        bash "$proj/scripts/behavior-scan-codex.sh"    --out-dir="$raw" 2>/dev/null
GEMINI_HOME="$workdir/gemini-fixture"      bash "$proj/scripts/behavior-scan-gemini.sh"   --out-dir="$raw" 2>/dev/null
OPENCODE_DB="$workdir/opencode-fixture/opencode.db" bash "$proj/scripts/behavior-scan-opencode.sh" --out-dir="$raw" 2>/dev/null

# All 4 jsonls produced (validate_schema may warn about gemini empty cwd but that's OK)
[ -s "$raw/claude.jsonl" ]   || { echo "FAIL: claude.jsonl empty"; exit 1; }
[ -s "$raw/codex.jsonl" ]    || { echo "FAIL: codex.jsonl empty"; exit 1; }
[ -s "$raw/gemini.jsonl" ]   || { echo "FAIL: gemini.jsonl empty"; exit 1; }
[ -s "$raw/opencode.jsonl" ] || { echo "FAIL: opencode.jsonl empty"; exit 1; }

# === Step 3: Run extractor → merged-signals.md ===
merged="$workdir/merged-signals.md"
bash "$proj/scripts/correction-extractor.sh" --src="$raw" --out="$merged"
[ -s "$merged" ] || { echo "FAIL: merged-signals.md empty"; exit 1; }
# All 4 corrections should appear
grep -q "不要 sed 盲改" "$merged"      || { echo "FAIL: claude marker missing"; exit 1; }
grep -q "必须 read"     "$merged"      || { echo "FAIL: codex marker missing"; exit 1; }
grep -q "don't bypass"  "$merged"      || { echo "FAIL: gemini marker missing"; exit 1; }
grep -q "always verify" "$merged"      || { echo "FAIL: opencode marker missing"; exit 1; }

# === Step 4: Simulate kernel inject — synthesize a kernel dir ===
# render-claude.sh reads from common-kernel/rules/*.md (not common-kernel/CLAUDE.md)
kernel_dir="$workdir/kernel"
mkdir -p "$kernel_dir/common-kernel/rules"
{
  cat <<MD
# Base section
Hello v1.3 pipeline test.

## Behavioral Signals (injected from merged-signals.md)
MD
  cat "$merged"
} > "$kernel_dir/common-kernel/rules/00-base.md"

# kernel-meta.yaml (minimal — apply.sh validates presence)
cat > "$kernel_dir/common-kernel/kernel-meta.yaml" <<META
version: 1.3.0-test
hosts: [test-host]
generated_at: 2026-05-11T00:00:00Z
META

# === Step 5: Run apply.sh against fake_home ===
HOME="$fake_home" bash "$proj/scripts/apply.sh" --target=claude --kernel="$kernel_dir" --apply --force

# === Step 6: Assertions ===
[ -f "$fake_home/.claude/CLAUDE.md" ] || { echo "FAIL: ~/.claude/CLAUDE.md missing"; exit 1; }
[ -f "$fake_home/.config/opencode/AGENTS.md" ] || { echo "FAIL: opencode AGENTS.md missing"; exit 1; }

# Both files contain markers from merged-signals.md
grep -q "不要 sed 盲改" "$fake_home/.claude/CLAUDE.md"          || { echo "FAIL: claude target missing marker"; exit 1; }
grep -q "不要 sed 盲改" "$fake_home/.config/opencode/AGENTS.md" || { echo "FAIL: opencode target missing marker"; exit 1; }

# OpenCode export header marker
head -1 "$fake_home/.config/opencode/AGENTS.md" | grep -q 'claudemex v1.3 opportunistic export' \
  || { echo "FAIL: opencode export missing v1.3 header"; exit 1; }

# Byte-equal body (AGENTS.md line 2 onward == CLAUDE.md in full)
tail -n +2 "$fake_home/.config/opencode/AGENTS.md" > "$workdir/oc-body"
diff -q "$fake_home/.claude/CLAUDE.md" "$workdir/oc-body" \
  || { echo "FAIL: opencode body diverges from claude target"; exit 1; }

echo "PASS test-e2e-full-pipeline.sh"
