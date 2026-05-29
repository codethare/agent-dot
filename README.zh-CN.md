# agent-dot

AI 智能体工具的点文件仓库 — 包含 OpenCode 智能体技能定义、配置文件及 Shell 环境设置。

## 目录结构

```
.agents/skills/     AI 智能体技能定义（代码审查、TDD、浏览器自动化等）
.config/opencode/   OpenCode AI 编程助手配置
.config/tmux/       tmux 终端复用器配置
.config/just/       just 命令运行器配置
.omp/agent/         oh-my-openagent 提供商和模型配置
.bashrc             Shell 别名、PATH 管理和环境变量
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

## 前置依赖

- [OpenCode](https://opencode.ai) — AI 编程助手（使用智能体功能必需）
- [tmux](https://github.com/tmux/tmux) — 终端复用器
- [just](https://github.com/casey/just) — 命令运行器（可选）
- [oh-my-openagent](https://github.com/codethare/oh-my-openagent) — 智能体框架（可选）
- [exa](https://github.com/ogham/exa) — 现代 `ls` 替代工具（为别名提供支持）

## 许可证

MIT — 详见 [LICENSE](LICENSE)。
