# agent-dot

Dotfiles for AI agent tooling — OpenCode agent skills, configuration files, and shell environment setup.

## Structure

```
.agents/skills/     AI agent skill definitions (code review, TDD, browser automation, etc.)
.config/opencode/   OpenCode AI coding assistant configuration
.config/tmux/       tmux terminal multiplexer configuration
.config/just/       just command runner configuration
.omp/agent/         oh-my-openagent provider and model configuration
.bashrc             Shell aliases, PATH management, and environment variables
LICENSE             MIT License
```

## Components

### Agent Skills (`.agents/skills/`)

A collection of reusable agent skills covering code review, test-driven development, deep-module design, security hardening, browser automation, commit message generation, and more. Each skill is self-contained as a `SKILL.md` with optional references and templates.

### OpenCode Configuration (`.config/opencode/`)

- **opencode.jsonc** — Plugin, permission, LSP, MCP, and compaction settings
- **AGENTS.md** — Global instructions governing agent behaviour
- **CLAUDE.md** — Per-project agent conventions

### Shell Environment (`.bashrc`)

- Common aliases (`ls`, `grep`, `tree`, directory navigation)
- `exa`-based enhanced listing commands
- `PATH` management for `~/.local/bin`, `~/.bun/bin`, `~/.claude/omc`, and mise shims

### Terminal Multiplexer (`.config/tmux/`)

Modular tmux configuration with separate files for status line, theme, key bindings, and utility settings.

## Getting Started

### Using a Dotfile Manager

If you use [rtk](https://github.com/codethare/rtk) or any dotfile manager that supports stow-style deployment:

```bash
rtk deploy agent-dot
```

### Manual Symlinks

```bash
ln -sf ~/agent-dot/.bashrc ~/.bashrc
ln -sf ~/agent-dot/.config/opencode ~/.config/opencode
ln -sf ~/agent-dot/.config/tmux ~/.config/tmux
```

## Prerequisites

- [OpenCode](https://opencode.ai) — AI coding assistant (for agent features)
- [tmux](https://github.com/tmux/tmux) — terminal multiplexer
- [just](https://github.com/casey/just) — command runner (optional)
- [oh-my-openagent](https://github.com/codethare/oh-my-openagent) — agent framework (optional)
- [exa](https://github.com/ogham/exa) — modern `ls` replacement (for shell aliases)

## License

MIT — see [LICENSE](LICENSE).
