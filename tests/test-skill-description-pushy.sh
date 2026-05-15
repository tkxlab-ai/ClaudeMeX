#!/usr/bin/env bash
# usage: test-skill-description-pushy.sh
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proj=$(cd "$here/.." && pwd)
desc=$(grep "^description:" "$proj/skills/claudemex/SKILL.md" | head -1)
[ -n "$desc" ] || { echo "FAIL: no description: line in SKILL.md"; exit 1; }

# Criterion 1: contains at least one pushy phrase
echo "$desc" | grep -qE "whenever|make sure to use|even if" \
  || { echo "FAIL: description missing pushy phrase (whenever/make sure to use/even if)"; exit 1; }

# Criterion 2: contains all 4 CLI names
for cli in "Claude Code" "Codex" "Gemini" "OpenCode"; do
  echo "$desc" | grep -q "$cli" \
    || { echo "FAIL: description missing CLI name '$cli'"; exit 1; }
done

# Criterion 3: at least one of behavior / 行为 / CLAUDE.md / 配置生成
echo "$desc" | grep -qE "behavior|行为|CLAUDE\\.md|配置生成" \
  || { echo "FAIL: description missing topic keyword"; exit 1; }

# Criterion 4: length cap 1024 chars
len=${#desc}
[ "$len" -le 1024 ] || { echo "FAIL: description $len chars > 1024 cap"; exit 1; }

echo "PASS test-skill-description-pushy.sh (description $len chars, all 4 criteria met)"
