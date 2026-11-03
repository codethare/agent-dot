# Usage

`bootstrap/` stores the Pi agent config this machine runs, plus the small XDG
configs of the tools that hang off it. Three scripts move state in and out; the
path map in `bootstrap/lib.sh` is the only place a tracked path is named.

| Direction | Command |
|---|---|
| machine → repo | `bash bootstrap/capture.sh [--commit]` |
| repo ↔ machine | `bash bootstrap/verify.sh` |
| repo → machine | `bash bootstrap/install.sh [--dry-run] [--force] [--only a,b]` |

Run all three from the repo root. `AGENT_BOOTSTRAP_HOME` overrides the home root
for all three (used by the tests); everything else reads `$HOME`.

## What is tracked

`map_entries` in `bootstrap/lib.sh` lists one row per path:
`<repo_rel> <home_rel> <file|tree>`.

- `file` — copied through `bootstrap/sanitize.py`, stored under `bootstrap/files/`.
- `tree` — copied verbatim (no sanitizing inside a tree).

Currently 18 entries: `~/.pi/agent` (7 files + `themes/`, `extensions/`),
`~/.config/{herdr,ponytail,rpiv-advisor,openspec,codebase-index}`,
`~/.config/systemd/user/skills-pull.{service,timer}`, and
`~/.local/bin/skills-pull`.

Not tracked: session history, package trees, caches, working notes, and every
secret value.

## Capture

```bash
bash bootstrap/capture.sh            # write into bootstrap/, review the diff
bash bootstrap/capture.sh --commit    # same, then commit bootstrap/ only
```

What it does:

1. Refuses to run when non-`bootstrap/` changes are staged — the capture commit
   would carry them along.
2. Copies each mapped path. A symlinked or missing source is warned about and
   skipped, never followed.
3. Regenerates `bootstrap/manifests/pi-packages.json` from the captured
   `settings.json`, so the package manifest cannot drift from what Pi reads.
4. Regenerates `bootstrap/manifests/skills-repos.txt` from the `origin` remotes
   under `~/skills/*`. Skill repos are recorded by remote, not by content.
5. Runs the leak scan over all of `bootstrap/` with `bootstrap/leak-patterns.txt`
   (API keys, tokens, `Bearer`, absolute `/home/...` paths). Any hit aborts
   before committing; fix the source or add a rule, do not commit around it.

## Backup workflow

```bash
bash bootstrap/verify.sh                # what drifted since the last capture
bash bootstrap/capture.sh               # rewrite bootstrap/files + manifests
bash bootstrap/capture.sh --commit      # local commit, bootstrap/ only
git push                                # your call, nothing pushes on its own
```

- Each capture is a full snapshot of the mapped paths, not a delta; the delta
  is just `git diff bootstrap`.
- Review before committing: the repo is the backup, and a bad capture of a
  secret is committed history.
- If the leak scan aborts, fix the source value or add a rule to
  `leak-patterns.txt`; do not bypass the scan.
- Restoring an earlier snapshot is ordinary git:
  `git checkout <sha> -- bootstrap/` then `bash bootstrap/install.sh`.
- Not backed up: session history and logs under `~/.pi/agent`, installed
  package trees, caches, `~/skills` repo contents (remotes only), and every
  value listed in `secrets.checklist.md`.

## Sanitizing

`sanitize.py` is keyed by path relative to home. Rules:

| Path | Change |
|---|---|
| `.pi/agent/settings.json` | drop `lastChangelogVersion`, `extensionChangelogVersions` |
| `.pi/agent/pi-ntfy.json` | blank `topic` |
| `.config/openspec/config.json` | drop `telemetry.anonymousId` |

Any other path is copied byte for byte. `verify.sh` compares sanitized hashes,
so those three values never count as drift.

## Verify

```bash
bash bootstrap/verify.sh   # exit 0 = matches, exit 1 = drift listed
```

Checks, one line per difference:

- `missing:` / `untracked:` / `modified:` / `extra:` for every mapped file and tree
- `missing package:` and `unmanaged package:` against `pi-packages.json`
  (`pi list` is the machine side)
- `skills repo remote differs:` against `skills-repos.txt`
- `drift: timer not enabled` when `skills-pull.timer` is not enabled
- tool versions for `pi bun mise herdr`, `missing tool:` when absent

Run it after `install.sh`, and any time you want to know whether the machine
still matches the repo.

## Install on a fresh machine

```bash
git clone https://github.com/codethare/agent-dot ~/.dot/agent-dot
cd ~/.dot/agent-dot
bash bootstrap/install.sh --dry-run   # read the plan first
bash bootstrap/install.sh
bash bootstrap/verify.sh
```

Steps, in order, selectable with `--only`:

| Step | Does |
|---|---|
| `preflight` | needs `git`, `python3`; refuses root; warns off Arch or if npm registry is unreachable |
| `packages` | `sudo pacman -S --needed - < manifests/pacman.txt` |
| `mise` | `mise use -g` each line of `manifests/mise-tools.txt` |
| `bunglobals` | `bun add -g` each line of `manifests/bun-globals.txt` |
| `pifiles` | copies every mapped path, mode 0644 except `skills-pull` (0755) |
| `pipackages` | `pi update --extensions`, installs anything missing from the manifest, re-copies tracked `settings.json` to restore extension filters, retries once |
| `skills` | git-clones each missing repo from `skills-repos.txt` into `~/skills/<name>` |
| `timer` | `systemctl --user daemon-reload`, `enable --now skills-pull.timer` |
| `report` | prints `secrets.checklist.md`, package/skills gaps, tool versions |

Safety behavior:

- Idempotent and resumable: existing files are backed up to
  `<target>.pre-restore.<UTC stamp>` before being overwritten. `--force` skips
  the backups.
- Refuses to write through a symlink in the target path (or above it) — replace
  the link with a real file or directory.
- `--dry-run` prints every copy and command without changing anything, including
  `pacman`.
- The `packages` step still needs `sudo`; everything else runs as you.

Then set the keys in `bootstrap/secrets.checklist.md` (`COMMAND_CODE_API_KEY`,
a fresh ntfy topic) and start Pi once. The tracked `pi-ntfy.json` has an empty
topic, so notifications stay off until you set one.

## skills-pull

`~/.local/bin/skills-pull` runs `git -C <repo> pull --ff-only` for every repo
under `~/skills`, and `skills-pull.timer` runs it daily. `--ff-only` means a
diverged clone reports `FAILED` instead of creating a merge.

```bash
systemctl --user list-timers skills-pull.timer
systemctl --user start skills-pull.service
journalctl --user -u skills-pull.service
```

## Adding a tracked path

1. Add a row to `map_entries` in `bootstrap/lib.sh`; if the file is executable,
   teach `entry_mode` as well.
2. Add a sanitize rule in `sanitize.py` if the file carries volatile or secret
   values.
3. `bash bootstrap/capture.sh`, review the diff, then `--commit`.
4. `bash tests/run.sh` and `bash bootstrap/verify.sh`.

## Tests

```bash
bash tests/run.sh
```

Sourced from `tests/test_*.sh` against a sandbox home under `$TMP`, with fake
`pi` and `systemctl` on `PATH`. Covers sanitize rules and hash stability,
capture skipping symlinks and refusing staged noise, install step selection /
backup / symlink refusal / dry-run, and every verify drift line. No network, no
real home, no packages — but also no coverage of a real `pacman`, `mise`, or
`pi install`.
