# agent-dot

AI 智能体工具的点文件仓库 — 包含 OpenCode 智能体技能定义、配置文件及 Shell 环境设置。

## 目录结构

```text
.agents/skills/     AI 智能体技能定义（代码审查、TDD、浏览器自动化等）
.config/opencode/   OpenCode AI 编程助手配置
.config/tmux/       tmux 终端复用器配置
.config/just/       just 命令运行器配置
.omp/agent/         oh-my-openagent 提供商和模型配置
.bashrc             Shell 别名、PATH 管理和环境变量
bootstrap/          Pi 智能体配置备份：capture、install、verify
docs/USAGE.md       备份/恢复完整指南
LICENSE             MIT 许可证
```

## 组件说明

### 智能体技能 (`.agents/skills/`)

可复用的智能体技能集合，涵盖代码审查、测试驱动开发、深层模块设计、安全加固、浏览器自动化、提交信息生成等功能。每个技能以 `SKILL.md` 文件为基础，附带参考文档和模板。

### OpenCode 配置 (`.config/opencode/`)

- **opencode.jsonc** — 插件、权限、LSP、MCP 及压缩设置
- **AGENTS.md** — 智能体行为全局指令
- **CLAUDE.md** — 项目级智能体约定

### Shell 环境 (`.bashrc`)

- 常用别名（`ls`、`grep`、`tree`、目录导航）
- 基于 `exa` 的增强文件列表命令
- `PATH` 管理：`~/.local/bin`、`~/.bun/bin`、`~/.claude/omc` 及 mise shims

### 终端复用器 (`.config/tmux/`)

模块化的 tmux 配置，状态栏、主题、快捷键及实用设置分文件管理。

## 快速开始

### 使用点文件管理器

如果使用 [rtk](https://github.com/codethare/rtk) 或其他支持 stow 方式部署的点文件管理器：

```bash
rtk deploy agent-dot
```

### 手动创建符号链接

```bash
ln -sf ~/agent-dot/.bashrc ~/.bashrc
ln -sf ~/agent-dot/.config/opencode ~/.config/opencode
ln -sf ~/agent-dot/.config/tmux ~/.config/tmux
```

## 备份与恢复

`bootstrap/` 保存本机实际在用的 Pi 智能体配置，以及挂在它下面的几个小型
XDG 配置。三个脚本负责进出；被跟踪的路径只在 `bootstrap/lib.sh` 的路径表里
出现一次。

| 方向 | 命令 |
| --- | --- |
| 机器 → 仓库 | `bash bootstrap/capture.sh [--commit]` |
| 仓库 ↔ 机器 | `bash bootstrap/verify.sh` |
| 仓库 → 机器 | `bash bootstrap/install.sh [--dry-run] [--force] [--only a,b]` |

三个脚本都在仓库根目录运行。`AGENT_BOOTSTRAP_HOME` 可以覆盖三者的 home 根目录
（测试用它），其余情况读 `$HOME`。

### 跟踪范围

`bootstrap/lib.sh` 里的 `map_entries` 每行一个路径：
`<repo_rel> <home_rel> <file|tree>`。

- `file` — 经 `bootstrap/sanitize.py` 处理后存到 `bootstrap/files/`。
- `tree` — 原样复制，树内不做 sanitize。

当前 18 条：`~/.pi/agent`（7 个文件 + `themes/`、`extensions/`）、
`~/.config/{herdr,ponytail,rpiv-advisor,openspec,codebase-index}`、
`~/.config/systemd/user/skills-pull.{service,timer}`，以及
`~/.local/bin/skills-pull`。

不跟踪：会话历史、包目录、缓存、工作笔记，以及任何密钥值。

### Capture（机器 → 仓库）

```bash
bash bootstrap/capture.sh            # 写入 bootstrap/，先看 diff
bash bootstrap/capture.sh --commit   # 同上，然后只提交 bootstrap/
```

它做的事：

1. 如果暂存区里有 `bootstrap/` 之外的改动就拒绝运行 —— 否则提交会把它们一起带走。
2. 复制每个被跟踪路径。源是符号链接或不存在时只警告并跳过，绝不跟随。
3. 用捕获到的 `settings.json` 重新生成 `bootstrap/manifests/pi-packages.json`，
   包清单不会和 Pi 实际读到的内容脱节。
4. 用 `~/skills/*` 下的 `origin` 远端重新生成
   `bootstrap/manifests/skills-repos.txt`。技能仓库只记远端，不记内容。
5. 用 `bootstrap/leak-patterns.txt` 扫描整个 `bootstrap/`（API key、token、
   `Bearer`、绝对 `/home/...` 路径）。命中即在提交前中止；改源头或加规则，
   不要绕过扫描。

### 备份流程

```bash
bash bootstrap/verify.sh                # 上次捕获后漂移了什么
bash bootstrap/capture.sh               # 重写 bootstrap/files 与清单
bash bootstrap/capture.sh --commit      # 本地提交，仅 bootstrap/
git push                                # 由你决定，脚本从不推送
```

- 每次 capture 都是被跟踪路径的完整快照，不是增量；增量就是 `git diff bootstrap`。
- 提交前先看：仓库就是备份，把密钥错捕进去就是写进历史。
- leak 扫描中止时，改源头值或往 `leak-patterns.txt` 加规则，不要跳过扫描。
- 恢复历史快照就是普通 git：`git checkout <sha> -- bootstrap/`，再跑
  `bash bootstrap/install.sh`。
- 不备份：`~/.pi/agent` 下的会话历史与日志、已安装的包目录、缓存、
  `~/skills` 仓库内容（只记远端），以及 `secrets.checklist.md` 里列出的每个值。

### Sanitize 规则

`sanitize.py` 以相对 home 的路径为键。规则：

| 路径 | 改动 |
| --- | --- |
| `.pi/agent/settings.json` | 删除 `lastChangelogVersion`、`extensionChangelogVersions` |
| `.pi/agent/pi-ntfy.json` | 把 `topic` 置空 |
| `.config/openspec/config.json` | 删除 `telemetry.anonymousId` |

其他路径逐字节复制。`verify.sh` 比较的是 sanitize 之后的哈希，所以这三个值
永远不会算作漂移。

### Verify（仓库 ↔ 机器）

```bash
bash bootstrap/verify.sh   # exit 0 = 一致，exit 1 = 列出漂移
```

检查项，每个差异一行：

- 每个被跟踪文件与树的 `missing:` / `untracked:` / `modified:` / `extra:`
- 对照 `pi-packages.json` 的 `missing package:` 与 `unmanaged package:`
  （机器一侧读 `pi list`）
- 对照 `skills-repos.txt` 的 `skills repo remote differs:`
- 未启用 `skills-pull.timer` 时的 `drift: timer not enabled`
- `pi bun mise herdr` 的版本，缺失时报 `missing tool:`

`install.sh` 之后跑一次；之后想知道机器是否仍与仓库一致，随时再跑。

### 在新机器上安装

```bash
git clone https://github.com/codethare/agent-dot ~/.dot/agent-dot
cd ~/.dot/agent-dot
bash bootstrap/install.sh --dry-run   # 先读一遍计划
bash bootstrap/install.sh
bash bootstrap/verify.sh
```

步骤按顺序执行，可用 `--only` 挑选：

| 步骤 | 作用 |
| --- | --- |
| `preflight` | 需要 `git`、`python3`；拒绝 root；非 Arch 或 npm registry 不可达时警告 |
| `packages` | `sudo pacman -S --needed - < manifests/pacman.txt` |
| `mise` | 对 `manifests/mise-tools.txt` 每行执行 `mise use -g` |
| `bunglobals` | 对 `manifests/bun-globals.txt` 每行执行 `bun add -g` |
| `pifiles` | 复制每个被跟踪路径，权限 0644，仅 `skills-pull` 为 0755 |
| `pipackages` | `pi update --extensions`，补装清单里缺的包，重拷受跟踪的 `settings.json` 恢复扩展过滤器，再重试一次 |
| `skills` | 按 `skills-repos.txt` 把缺失的仓库 clone 到 `~/skills/<name>` |
| `timer` | `systemctl --user daemon-reload`、`enable --now skills-pull.timer` |
| `report` | 打印 `secrets.checklist.md`、缺失的包/技能仓库、工具版本 |

安全行为：

- 幂等、可续跑：覆盖前把现有文件备份为 `<target>.pre-restore.<UTC 时间戳>`。
  `--force` 跳过备份。
- 目标路径（或其上层）是符号链接时拒绝写入 —— 先把链接换成真实文件或目录。
- `--dry-run` 打印每条复制与命令，什么都不改，`pacman` 也一样。
- `packages` 这一步仍需要 `sudo`，其余以你自己的身份运行。

然后设置 `bootstrap/secrets.checklist.md` 里的键（`COMMAND_CODE_API_KEY`、
一个新的 ntfy topic），并启动 Pi 一次。受跟踪的 `pi-ntfy.json` topic 为空，
设置之前不会推送通知。

### skills-pull

`~/.local/bin/skills-pull` 对 `~/skills` 下每个仓库执行
`git -C <repo> pull --ff-only`，`skills-pull.timer` 每天跑一次。`--ff-only`
意味着分叉的克隆会报 `FAILED`，而不是产生合并。

```bash
systemctl --user list-timers skills-pull.timer
systemctl --user start skills-pull.service
journalctl --user -u skills-pull.service
```

### 新增一条被跟踪路径

1. 在 `bootstrap/lib.sh` 的 `map_entries` 加一行；文件可执行的话，同时教会
   `entry_mode`。
2. 文件带易变值或密钥值时，在 `sanitize.py` 加一条规则。
3. `bash bootstrap/capture.sh`，看 diff，再 `--commit`。
4. `bash tests/run.sh` 与 `bash bootstrap/verify.sh`。

### 测试

```bash
bash tests/run.sh
```

由 `tests/test_*.sh` 组成，跑在 `$TMP` 下的沙箱 home 里，`PATH` 上是假的
`pi` 与 `systemctl`。覆盖 sanitize 规则与哈希稳定性、capture 跳过符号链接与
拒绝暂存噪音、install 的步骤选择/备份/拒绝符号链接/dry-run，以及 verify 的
每条漂移输出。不联网、不碰真实 home、不装包 —— 也因此没有覆盖真实的
`pacman`、`mise` 或 `pi install`。

## 前置依赖

- [OpenCode](https://opencode.ai) — AI 编程助手（使用智能体功能必需）
- [tmux](https://github.com/tmux/tmux) — 终端复用器
- [just](https://github.com/casey/just) — 命令运行器（可选）
- [oh-my-openagent](https://github.com/codethare/oh-my-openagent) — 智能体框架（可选）
- [exa](https://github.com/ogham/exa) — 现代 `ls` 替代工具（为别名提供支持）

## 许可证

MIT — 详见 [LICENSE](LICENSE)。
