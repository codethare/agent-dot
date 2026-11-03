# Agent config backup and restore

Date: 2026-11-03
Status: awaiting approval
Repo: `agent-dot` (origin `github.com/codethare/agent-dot`)

## Intent

Move the AI-agent configuration on this machine into one tracked place, and be able to
rebuild it on a fresh Arch machine — tools and Pi packages included — with two commands.

Why now: `agent-dot` tracks skills, an OpenCode config, and `.omp`, none of which are what this
machine actually runs. The live `~/.pi/agent` config is untracked, and `~/.config/opencode` and
`~/.omp` do not exist in `$HOME` at all. The repo and the machine disagree today.

Drift is continuous, not occasional: during the session that wrote this document, Pi rewrote
`~/.pi/agent/settings.json` without any user action. The old file listed
`+extensions/nvim-approve.ts` — a file that has never existed in `extensions/` — and the new one
does not. Nothing recorded either state.

## Goals

- One repo (`agent-dot`) is the single source of truth for agent configuration.
- `capture.sh` copies the live config into the repo and reports, without committing, what changed.
- `install.sh` rebuilds the environment on a fresh Arch machine, idempotently, resumable step by step.
- `verify.sh` reports any difference between repo and machine, and exits non-zero on drift.
- No secret value ever enters the repo.

## Non-goals

- Secret values, tokens, API keys, auth state. The repo records *names* that must be set by hand.
- Session history, npm trees, git clones, caches, per-project workflow state.
- Desktop dotfiles (fish, nvim, tmux, sway). They belong to `~/.dot/dot`; this design only checks
  the shell prerequisites agent tools need.
- Restoring OpenCode. It is not installed on this machine; its repo files stay as-is, out of the
  install path, until it is actually used.

## Anti-goals

Any of these means the design failed, even if the scripts run:

- `install.sh` exits 0 while Pi cannot start, or packages are silently missing.
- `capture.sh` commits a secret, or an absolute machine-specific path that breaks a restore.
- `verify.sh` passes while the machine and the repo disagree.
- `install.sh` overwrites a config the user hand-edited on the new machine without a copy.

## Constraints

- Arch Linux, `pacman`; `git`, `bun`, `mise`, `python3` are the only tools the scripts may assume.
- `~/.pi/agent` must stay writable by Pi itself; Pi rewrites `settings.json` when it installs or
  updates packages.
- Scripts are `bash`, `set -euo pipefail`, English output and comments.
- Repo content stays reviewable: plain files, no archives, no generated binaries.

## Approaches considered

**A. Repo as source of truth, three scripts (chosen).** `capture`, `install`, `verify` share one
file map. No new dependency; every change is a reviewable commit; `verify` makes drift visible.
Cost: the file map is code that must be maintained, and capture is a deliberate step rather than
continuous.

**B. chezmoi.** Idempotent `apply`, built-in diff, permission handling, templating for machine
differences. Cost: one more tool to bootstrap before anything else works; and Pi writes
`settings.json` on package install, so two writers would own the same file — someone has to lose.

**C. Archive (tar + age) to remote storage.** Fastest to build. Cost: opaque restore, no history,
drift invisible — exactly the failure already present in `agent-dot`.

A was chosen: it adds no dependency, makes "what to install" an auditable list, and its `verify`
step addresses the drift that motivated this work.

## Repo layout

```text
bootstrap/
  install.sh          repo -> fresh machine
  capture.sh          machine -> repo
  verify.sh           repo vs machine
  lib.sh              file map, sanitize, logging, dry-run
  manifests/
    pacman.txt         git, bun, mise, fish, tmux
    mise-tools.txt     herdr=latest
    bun-globals.txt    Pi CLI, codegraph, openspec
    pi-packages.json   generated verbatim from settings.json "packages"
    skills-repos.txt   generated: name<TAB>clone-url
  files/
    pi/               mirror of selected ~/.pi/agent paths
    xdg/herdr/config.toml, xdg/herdr/.plugins.lock
    xdg/ponytail/config.json
    xdg/rpiv-advisor/advisor.json
    xdg/openspec/config.json
    xdg/codebase-index/config.json
    systemd/user/skills-pull.service, skills-pull.timer
    bin/skills-pull
  secrets.checklist.md   required variable names, no values
docs/superpowers/specs/  this document
```

## File map

Included, with their source path:

| Repo path | Source |
| --- | --- |
| `files/pi/AGENTS.md`, `settings.json`, `keybindings.json`, `.mcp.json`, `commandcode-models.json`, `sandbox.json` | `~/.pi/agent/` |
| `files/pi/themes/` | `~/.pi/agent/themes/` |
| `files/pi/extensions/` | `~/.pi/agent/extensions/` |
| `files/pi/docs/` | `~/.pi/agent/docs/` |
| `files/xdg/herdr/config.toml`, `.plugins.lock` | `~/.config/herdr/` |
| `files/xdg/{ponytail,rpiv-advisor,openspec,codebase-index}/` | `~/.config/<tool>/` |
| `files/systemd/user/skills-pull.{service,timer}` | `~/.config/systemd/user/` |
| `files/bin/skills-pull` | `~/.local/bin/skills-pull` |

`~/.config/mise/config.toml` is not in the map: step 3 lets `mise` edit it, so tools other than
`herdr` cannot be clobbered by a restore.

Excluded, with reason:

| Path | Reason |
|---|---|
| `~/.pi/agent/sessions/` | 232M conversation history; not configuration |
| `~/.pi/agent/npm/` | 1G package tree; Pi rebuilds it |
| `~/.pi/agent/git/` | 39M package clones; Pi rebuilds them |
| `fff/`, `.pi-lens/`, `web-search-cache/`, `pi-cache-optimizer-stats.d/` | caches |
| `mcp-cache.json`, `mcp-last-seen-version.json`, `mcp-onboarding.json`, `mcp-project-approvals.json`, `models-store.json`, `next-suggestion.json`, `run-history.jsonl`, `pi-subagents/`, `pi-web-access/` | runtime state |
| `auth.json` | credentials |
| `trust.json` | 18 absolute project paths; restoring it would pre-approve directories that do not exist on the new machine |
| `pi-ntfy.json` | the ntfy topic is a capability: anyone with it can read the notifications |
| `*.test.ts`, `.settings.json.bak*` | development artifacts |
| `~/.pi/workflows/`, `~/.pi/context-mode/`, `~/.pi/cache/` | per-project state, 29M of index data, cache |
| `~/.config/herdr/session-snapshots/`, `*.log`, `release-notes.json`, `session*.json` | session state |
| `~/.config/fish/`, `~/.config/nvim/`, `~/.config/*` desktop tools | owned by `~/.dot/dot` |

## Sanitize rules

Applied by both `capture.sh` and `verify.sh`, so the comparison is against the sanitized form:

- `pi/settings.json`: drop `lastChangelogVersion` and `extensionChangelogVersions`. Pi rewrites
  both on its own; keeping them turns every package update into repo churn.
- `xdg/openspec/config.json`: drop `telemetry.anonymousId`. It is a persistent identifier and has
  no effect on behaviour.

JSON transforms use `python3 -m json.tool`-style stdlib code in `lib.sh`. No `jq` dependency.

## `capture.sh` (machine -> repo)

1. Refuse to start if the repo has staged changes outside `bootstrap/`.
2. Copy every mapped path into `files/`, applying the sanitize rules.
3. Regenerate `manifests/pi-packages.json` from `settings.json` (verbatim, object entries and
   their `extensions` filters included), `manifests/skills-repos.txt` from the remotes of
   `~/skills/*`.
4. Leak scan across every file that changed: `COMMAND_CODE_API_KEY`, `API_KEY=`, `TOKEN=`,
   `SECRET=`, `sk-`, `ghp_`, `xox[bp]-`, `Bearer `, plus any `$HOME`-absolute path inside a
   tracked file. On a hit: print `file:line`, delete nothing, exit non-zero.
5. With `--commit`: `git add` the affected paths and commit
   `chore(bootstrap): capture agent config`. Without it: print `git status` and stop.

## `install.sh` (repo -> fresh machine)

Steps, each idempotent and individually addressable with `--only <step>`:

0. **own PATH** — the script prepends `$HOME/.bun/bin`, `$HOME/.local/bin`, and
   `$HOME/.local/share/mise/shims` to its own `PATH`, because bash on a fresh machine has none of
   them. It never edits shell config; if the interactive shell would still miss them, it says so.
1. **preflight** — Arch or warn; not root; `git`, `python3` present; network reachable.
2. **packages** — `pacman -S --needed - < manifests/pacman.txt`.
3. **mise** — `mise use -g herdr@latest` (writes the `[tools]` entry itself, so other tools in
   `~/.config/mise/config.toml` survive), then `mise install`.
4. **bun globals** — `bun add -g` for each entry in `manifests/bun-globals.txt`.
5. **pi files** — copy `files/pi/**` into `~/.pi/agent/`, after writing the current version to
   `<target>.pre-restore.<UTC>`. Same for `files/xdg/**`.
6. **pi packages** — `pi update --extensions`; non-zero exit is fatal, and the failing source is
   named. If `update` reports nothing to do, fall back to one `pi install` per entry in
   `pi-packages.json`, object entries included, so extension filters are not dropped.
7. **skills** — `git clone <url> ~/skills/<name>` for each missing entry; never touch an existing
   directory.
8. **timer** — install `skills-pull` into `~/.local/bin` (`0755`), write the two units,
   `systemctl --user daemon-reload`, `enable --now skills-pull.timer`.
9. **report** — print `secrets.checklist.md`, then smoke checks: `pi --version`, `pi list`
   matching every source in `pi-packages.json`, `git -C ~/skills/* status`, `herdr --version`.
   The bar is tooling and package resolution, not a provider round-trip: without the key nothing
   can send a message, so the report ends with that one manual check.

Flags: `--dry-run` (print, change nothing), `--only <step>`, `--force` (overwrite without a
`.pre-restore` copy; only for a target already managed by this script). Any failed step stops the
run and names itself — no partial success reported as success.

## `verify.sh` (repo vs machine)

Compares, per mapped file, the sanitized hash; lists missing, extra-tracked, and modified files.
Then checks: `pi list` sources equal `pi-packages.txt`; each `~/skills/<name>` exists with the
expected remote; the timer is enabled; prints resolved versions (`pi`, `bun`, `mise`, `herdr`).
Exit 1 on any difference, 0 otherwise. Excluded paths are never reported — a machine having
sessions is not drift.

## Safety and idempotency

- Every overwrite leaves `<target>.pre-restore.<UTC>` unless `--force`.
- `pacman --needed`, `mise install`, `bun add -g`, `pi update --extensions`, `git clone` (skipped
  when present) and `systemctl enable --now` are all safe to repeat.
- `capture.sh` is read-only on `$HOME`; only `install.sh` writes there, and only inside mapped paths.
- Neither script deletes anything on the machine. Removal is a manual act.

## Secrets

Out of scope by request: no value is captured, compared, or restored. `secrets.checklist.md` lists
names only:

- `COMMAND_CODE_API_KEY` — read by the current provider setup.
- ntfy topic — regenerate, do not restore the old one.
- Pi OAuth providers, if any are added later: `pi auth`.

## Decisions made here, worth checking while reading

1. **Scope is agent tooling only.** Fish stays in `~/.dot/dot`; `install.sh` puts the three
directories on its own `PATH` and reports when the interactive shell lacks them, rather than
ownhing shell config in two repos.
2. **Copy, not symlinks.** Pi rewrites `settings.json`; whether it writes through a symlink or
   atomically renames is unverified, and a broken link would surface as a config that silently
   stops updating. `verify` covers the cost of copying.
3. **`trust.json` is deliberately not restored.** Trust is per machine and per directory.
4. **`pi-ntfy.json` is treated as a credential**, not as config.
5. **Volatile Pi keys are dropped on capture**, as listed under Sanitize rules.
6. **OpenCode and `.omp` stay in the repo but are not restored.** Leaving them in place keeps
   history; wiring them into `install.sh` would restore a tool this machine does not run.
7. **`herdr` stays on `latest`.** Pinning would freeze a fast-moving tool; `verify` prints the
   version so drift is visible instead.
8. **Generated manifests** (`pi-packages.json`, `skills-repos.txt`) are produced by capture and
   never hand-edited, so they cannot disagree with the machine.
9. **`install.sh` proves tooling and package resolution, not inference.** With keys out of scope,
   the last step is a printed manual check (send one message) instead of an automated one.

## Left to the builder

- Whether `pi update --extensions` installs a package listed in `settings.json` but absent from
  disk on a fresh machine, or whether the per-source `pi install` fallback is the real path.
  Verify on a throwaway `$HOME`, then keep one code path.
- Whether `mise install` needs `mise trust` for a freshly written `~/.config/mise/config.toml`.
- Whether `herdr` needs a first-run step before `herdr --version` succeeds.
- Script-level tests: `install.sh --dry-run` on this machine, plus a sandboxed `HOME` run for
  steps 5-9 (no root, no network for packages).
