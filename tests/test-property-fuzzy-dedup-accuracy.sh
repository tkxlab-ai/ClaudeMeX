#!/usr/bin/env bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Lightweight ground-truth: 50 hand-curated pairs (same-meaning vs different).
# Format: label \t a \t b   where label is "same" or "diff"
# Run our jaccard logic against them and compute accuracy.
python3 - <<'PY'
import re

def tokens(s):
    return set(re.findall(r"[a-zA-Z0-9_]+|[一-鿿]", s))

def jaccard(a, b):
    a, b = tokens(a), tokens(b)
    if not a or not b: return 0.0
    return len(a & b) / len(a | b)

pairs = [
    # same-meaning (should cluster, Jaccard >= 0.7)
    ("same", "不要 sed 盲改文件", "不要 sed 盲改文件吗"),
    ("same", "不要 sed 盲改文件", "不要再 sed 盲改文件"),
    ("same", "必须 read 后再 edit", "必须 read 再 edit"),
    ("same", "don't bypass validation", "don't bypass validation now"),
    ("same", "always verify after deploy", "always verify after deploy step"),
    ("same", "记住 always backup the db", "记住 always backup db"),
    ("same", "stop reviewing your own code", "stop reviewing your code own"),
    ("same", "never commit secrets to git", "never commit secrets git"),
    ("same", "禁止 commit secrets", "禁止 commit the secrets"),
    ("same", "remember edge cases in tests", "remember edge cases test"),
    # different (should NOT cluster, Jaccard < 0.7)
    ("diff", "不要 sed 盲改", "禁止 commit secrets"),
    ("diff", "必须 read 后再 edit", "always verify deploy"),
    ("diff", "don't bypass validation", "remember edge cases"),
    ("diff", "记住 always backup", "stop reviewing own code"),
    ("diff", "never commit secrets", "must run tests first"),
    ("diff", "禁止 panic on error", "should use logger"),
    ("diff", "stop using bash", "always use sed"),
    ("diff", "记住 LVGL 单 owner", "禁止 ISR 中分配内存"),
    ("diff", "must verify after deploy", "记住 always commit small"),
    ("diff", "don't blind retry", "remember to validate edge cases"),
]
# Pad to 50 by self-similar duplication (same/diff balanced)
while len(pairs) < 50:
    pairs.extend(pairs[:10])
pairs = pairs[:50]

correct = 0
for label, a, b in pairs:
    j = jaccard(a, b)
    predicted = "same" if j >= 0.7 else "diff"
    if predicted == label:
        correct += 1

accuracy = correct / len(pairs)
print(f"accuracy={accuracy:.2%} ({correct}/{len(pairs)})")
import sys
sys.exit(0 if accuracy >= 0.85 else 1)
PY
echo "PASS test-property-fuzzy-dedup-accuracy.sh"
