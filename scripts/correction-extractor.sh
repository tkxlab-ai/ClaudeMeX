#!/usr/bin/env bash
# usage: correction-extractor.sh --src=DIR --out=FILE
# correction-extractor.sh — merges per-CLI jsonl into merged-signals.md.
# Picks lines where kind=user and text begins with a correction marker
# (bilingual Chinese + English). Output is a Markdown bullet list with
# cumulative occurrence counts.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin

SRC=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --src=*) SRC="${1#--src=}";;
    --out=*) OUT="${1#--out=}";;
    *) echo "unknown: $1" >&2; exit 1;;
  esac; shift
done
[ -n "$SRC" ] && [ -n "$OUT" ] || { echo "missing --src/--out" >&2; exit 1; }
[ -d "$SRC" ] || { echo "src not a dir: $SRC" >&2; exit 1; }

python3 - "$SRC" "$OUT" <<'PY'
import json, sys, re, pathlib, collections
src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])

# Bilingual markers — start-of-line anchored so we don't catch incidental
# occurrences mid-message ("when 必须 X" isn't a directive about X).
markers_zh = [r"^\s*不要\s+", r"^\s*必须\s+", r"^\s*禁止\s+", r"^\s*不可以\s+", r"^\s*记住\s+", r"^\s*应该\s+"]
markers_en = [r"^\s*don'?t\s+", r"^\s*never\s+", r"^\s*always\s+", r"^\s*must\s+", r"^\s*stop\s+", r"^\s*remember\s+"]
patterns = [re.compile(p, re.I) for p in (markers_zh + markers_en)]

phrases = collections.Counter()
for p in sorted(src.glob("*.jsonl")):
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line: continue
        try: r = json.loads(line)
        except Exception: continue
        if r.get("kind") != "user": continue
        text = (r.get("text","") or "").strip()
        for pat in patterns:
            if pat.match(text):
                phrases[text[:80]] += 1
                break

# Fuzzy dedup: collapse phrases with token Jaccard >= 0.7 into one bucket.
# Tokenizer: ASCII words as units; each CJK ideograph as individual token.
# Using [a-zA-Z0-9_]+ instead of \w+ because Python's \w matches entire CJK
# runs as single tokens, which makes paraphrase Jaccard too low to dedup.
def tokens(s):
    return set(re.findall(r"[a-zA-Z0-9_]+|[一-鿿]", s))

merged = []   # list of (canonical_phrase, total_count, token_set)
for ph, n in phrases.most_common():
    tk = tokens(ph)
    if not tk:
        merged.append((ph, n, tk))
        continue
    hit = False
    for i, (mph, mn, mtk) in enumerate(merged):
        inter = len(tk & mtk)
        union = len(tk | mtk)
        if union and inter / union >= 0.7:
            merged[i] = (mph, mn + n, mtk)
            hit = True
            break
    if not hit:
        merged.append((ph, n, tk))

# Tie-break stability: sort by (-count, canonical_phrase) for cross-run determinism.
# Without this, equal-count phrases could re-order across Python runs (CPython
# dict insertion order is stable within a run but Counter.most_common() is not
# guaranteed stable for equal-count entries across versions).
merged.sort(key=lambda x: (-x[1], x[0]))

out.parent.mkdir(parents=True, exist_ok=True)
with out.open("w", encoding="utf-8") as fh:
    fh.write("# Merged correction signals (v1.3 input-side)\n\n")
    fh.write("> Aggregated across Claude / Codex / Gemini / OpenCode sessions.\n")
    fh.write("> Fuzzy-merged via token Jaccard >= 0.7.\n\n")
    for phrase, total, _tk in merged:
        fh.write(f"- {phrase}  (×{total})\n")
print(f"✓ merged-signals.md: {len(merged)} unique phrases (post-fuzzy)")
PY
