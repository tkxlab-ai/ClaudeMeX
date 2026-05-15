[English](README.md) | **简体中文**

![version](https://img.shields.io/badge/version-v1.3.3-blue)
![license](https://img.shields.io/badge/license-MIT-green)
![tests](https://img.shields.io/badge/tests-54%20pass%20%2F%200%20fail-brightgreen)
![audit](https://img.shields.io/badge/deep--audit-222%20checks-success)
![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)

# ClaudeMeX

> **让你的 AI 编码助手，按你_真实_的工作方式校准。**
> 一份提示词扫描你的真实 CLI 历史 → 生成贴合你习惯的配置。

---

## 为什么要有这个工具？

每一个 AI 编码 CLI —— Claude Code、OpenAI Codex、Gemini CLI、OpenCode ——
开箱时对你**一无所知**。于是每个人都从零手写 `CLAUDE.md`。这条路会崩：

| | 手写 `CLAUDE.md` | ClaudeMeX |
|---|---|---|
| **依据** | 靠猜 —— 你**以为**自己怎么工作 | 证据 —— 你被度量的 session 历史 |
| **新鲜度** | 习惯在变文件在老化 | 每 2 周重跑；追踪现实 |
| **多机** | 笔记本台式机各说各话 | 多数投票 common-kernel + 各机增量 |
| **多工具** | Codex 和 Claude 拿到不同规则 | 全 4 CLI 统一进一个内核 |
| **隐私** | 手动脱敏，易错 | cwd 自动折叠 + 16 类扫描门禁 |
| **成本** | 数小时手调，反复 | 一份提示词，~5–15 分钟，可重复 |

ClaudeMeX 用**证据**取代猜测。

## ClaudeMeX 是什么？

一套**元提示词 + 工具链**，**全程本机本地运行**：

1. **扫描** 你跨四个 CLI 工具的真实本地 session 历史。
2. **提取** 行为信号 —— 你真正做的纠正、你批准/拒绝的工具、真实时段画像、
   技术栈占比、任务分布。
3. **合并** 进单一内核做模糊去重，让"别盲改 sed"/"禁止 sed 盲改"无论在哪个
   工具里说过都收敛成一条带权重的规则。
4. **渲染** 按证据校准的分层 `CLAUDE.md`。
5. **部署**（带备份 + 隐私脱敏门禁），并机会性同步一份字节相同副本给 OpenCode。

不上传任何地方。

## 它产出什么（示例）

一次扫描把你的真实纠正提炼成带权重、去重的内核段（合成、已脱敏示例）：

```markdown
## §15 行为规则（来自 4-CLI session 扫描，90 天语料）

- 绝不盲改 sed —— 先 read 文件          (×23, claude+codex)
- 部署前必须验证 (curl/grep)            (×15, claude+opencode)
- 不要主动总结除非要求                  (×11, gemini+claude)
- 嵌入式静态分配，禁 malloc             (×7,  codex)

## §16 时段画像（内容时间戳，本地时区）
高峰 22:00–01:00 (52%) · 次峰 09:00–11:00（高专注 C 开发）
```

你拿到的是**从你真正做过的事推导出来的**，不是空模板。

## 更新日志

| 版本 | 日期 | 亮点 |
|------|------|------|
| **v1.3.3** | 2026-05-15 | 用最新 GitX 流水线重打包（深度审计 222 项）|
| **v1.3.2** | 2026-05-14 | prompt 加 Step 0c 多 CLI 清单 + pushy skill 描述 |
| **v1.3.1** | 2026-05-13 | 多 CLI 行为输入：4 readers + correction-extractor + 16 类脱敏 |
| **v1.3.0** | 2026-05-11 | TKX 统一安装标准 |

完整历史：[Releases](../../releases) · [CHANGELOG](Release/CHANGELOG.md)。

## 三个层级

| 需求 | 层级 | 约行数 | 首跑 | Token 预算 |
|------|------|--------|------|-----------|
| 新机器 / CI / Codex 32 KiB 上限 | **MIN** | ~160 | < 1 分钟 | ~17 K |
| 跨项目日常使用 | **COMMON** | ~480 | 3–5 分钟 | ~40 K |
| 全量项目档案主力机 | **MAX** | 1000+ | 5–15 分钟 | ~90 K+ |

MIN ⊂ COMMON ⊂ MAX。升降级无需重写任何东西。

## 多 CLI 行为输入（v1.3+）

| 工具 | 扫描源 |
|------|--------|
| **Claude Code** | `~/.claude/projects/*/*.jsonl` |
| **OpenAI Codex** | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` + `session_index.jsonl` |
| **Google Gemini** | `~/.gemini/history/<user>/*.json`（机会性）|
| **OpenCode** | `~/.local/share/opencode/opencode.db`（SQLite）|

`correction-extractor` 把纠正短语模糊合并（token Jaccard ≥ 0.7，中英双语标记）
进 `merged-signals.md`。

> **校准旋钮**：默认标记匹配陈述式指令（`don't X`、`必须 X`）。风格更间接？
> 按你的语料调 `scripts/correction-extractor.sh` 的标记列表。

## 隐私与安全

- **cwd 脱敏** —— `/Users/<本人>/…` → `~/…`，`/Users/<他人>/…` →
  `<他人>:~/…`；每个 reader 落盘前先做。
- **16 类扫描器** —— fail-closed 标记 cwd 泄漏、OAuth token、session-id
  UUID、凭证路径，作用于每个产物。
- **绝不外泄** —— `behavior-raw/` 在 gitignore + sanitize-ignore，从不
  commit、从不打包。
- **部署前备份** —— `apply.sh` 先备份，默认 dry-run。

## 前置要求

- **Claude Code**（`npm i -g @anthropic-ai/claude-code`）—— 宿主 CLI
- **bash 3.2+**、**python3**（纯标准库）、**git**
- **sqlite3** CLI —— 可选；仅 OpenCode reader 用（缺失则优雅跳过）
- macOS 或 Linux

## 安装

```bash
git clone https://github.com/tkxlab-ai/ClaudeMeX.git
cd ClaudeMeX
bash install.sh                     # → ~/.claude/skills/claudemex/
PREFIX=/your/path bash install.sh   # 自定义位置
bash install.sh --uninstall         # 卸载
```

重跑 `install.sh` 即升级。完整选项 + 8 节排障见 [INSTALL.md](INSTALL.md)。

## 快速开始

**最快（5 分钟 MIN-lite）**：打开 `Release/lite-prompt-MIN.md`，把标记块复制进
`~/.claude/CLAUDE.md`，改 `CCG_*` 占位符。

**完整生成**：

1. `npm i -g @anthropic-ai/claude-code`
2. 任意目录跑 `claude`
3. 把 `TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md` 粘进对话（或装完后用
   `/generate` skill 命令）
4. 等扫描 + 生成（5–15 分钟）
5. 部署：`bash Release/deploy.sh MIN ~/.claude/`（或 `COMMON` / `MAX`）

## 多机合并

每台机器跑生成器（Claude Code 里的 `/generate` skill 命令，或粘贴
`TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md`），同步 `outputs/` 目录
（Syncthing / git / tarball），然后在任意一台机器：

```bash
bash scripts/merge.sh --from=outputs --hosts=hostA,hostB
bash scripts/apply.sh --target=claude --apply   # 部署合并内核
```

章节级多数投票 → `common-kernel/`（一致规则）+ `per-machine-extension/`
（各机增量）。

## 仓库结构

```
TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md   粘进 CLI 的元提示词
skills/claudemex/                       可安装 skill 包
scripts/                                readers / extractor / merge / apply / redact-scan
tests/                                  6 层测试金字塔
Release/claudemex-vX.Y.Z/               release 包（.skill + checksums + SBOM）
docs/                                   设计 spec、plan、v1.4 路线图
```

## 测试

六层金字塔为每个 release 把门：**单元 → 属性 → 对抗 → 端到端 → 回归硬门禁
→ 独立红队评审**。每个 release 附冻结基线 + GitX 流水线 200+ 项深度审计。

## 分发

公开分发**仅 release 产物**：从 [Releases](../../releases) 下载
`claudemex-vX.Y.Z.skill`（附 `.skill`、`checksums.txt`、CycloneDX
`sbom.cyclonedx.json`）。完整源码树在私有镜像。

## 许可

MIT © 2026 TKXLAB.AI —— 见 [LICENSE](LICENSE)。
