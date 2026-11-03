#!/usr/bin/env bash
# Shared path map and helpers for capture.sh, install.sh, and verify.sh.
# Sourced, never executed directly, so it sets no shell options of its own.

BOOTSTRAP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(dirname "$BOOTSTRAP_DIR")
FILES_DIR="$BOOTSTRAP_DIR/files"
MANIFESTS_DIR="$BOOTSTRAP_DIR/manifests"
HOST_HOME=${AGENT_BOOTSTRAP_HOME:-$HOME}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
DRY_RUN=${DRY_RUN:-0}
FORCE=${FORCE:-0}

# One row per tracked path: <repo_rel><TAB><home_rel><TAB><file|tree>.
# The map is the single place a tracked path is named; capture, install, and
# verify all read it, so they cannot disagree about what is tracked.
map_entries() {
  printf '%s\t%s\t%s\n' \
    "pi/AGENTS.md"                     ".pi/agent/AGENTS.md"                     "file" \
    "pi/settings.json"                 ".pi/agent/settings.json"                 "file" \
    "pi/keybindings.json"              ".pi/agent/keybindings.json"              "file" \
    "pi/.mcp.json"                     ".pi/agent/.mcp.json"                     "file" \
    "pi/commandcode-models.json"       ".pi/agent/commandcode-models.json"       "file" \
    "pi/sandbox.json"                  ".pi/agent/sandbox.json"                  "file" \
    "pi/pi-ntfy.json"                  ".pi/agent/pi-ntfy.json"                  "file" \
    "pi/themes"                        ".pi/agent/themes"                        "tree" \
    "pi/extensions"                    ".pi/agent/extensions"                    "tree" \
    "xdg/herdr/config.toml"            ".config/herdr/config.toml"               "file" \
    "xdg/herdr/.plugins.lock"          ".config/herdr/.plugins.lock"             "file" \
    "xdg/ponytail/config.json"         ".config/ponytail/config.json"            "file" \
    "xdg/rpiv-advisor/advisor.json"    ".config/rpiv-advisor/advisor.json"       "file" \
    "xdg/openspec/config.json"         ".config/openspec/config.json"            "file" \
    "xdg/codebase-index/config.json"   ".config/codebase-index/config.json"      "file" \
    "systemd/user/skills-pull.service" ".config/systemd/user/skills-pull.service" "file" \
    "systemd/user/skills-pull.timer"   ".config/systemd/user/skills-pull.timer"   "file" \
    "bin/skills-pull"                  ".local/bin/skills-pull"                  "file"
}

repo_path() { printf '%s/%s\n' "$FILES_DIR" "$1"; }
host_path() { printf '%s/%s\n' "$HOST_HOME" "$1"; }

# File mode applied on restore; only the skills-pull script is executable.
entry_mode() {
  if [ "$1" = ".local/bin/skills-pull" ]; then echo 0755; else echo 0644; fi
}

sanitize_copy() { python3 "$BOOTSTRAP_DIR/sanitize.py" "$1" "$2" "$3"; }
sanitized_hash() { python3 "$BOOTSTRAP_DIR/sanitize.py" --hash "$1" "$2"; }

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

# Package sources declared in the manifest, one per line. Object entries keep
# their extension filters in the manifest; only the source is compared.
manifest_package_sources() {
  python3 - "$MANIFESTS_DIR/pi-packages.json" <<'PY'
import json
import sys

for entry in json.load(open(sys.argv[1])):
    print(entry if isinstance(entry, str) else entry["source"])
PY
}

# Package sources Pi reports as installed, one per line. `pi list` indents each
# source by two spaces and appends " (filtered)" for object entries.
installed_package_sources() {
  pi list 2>/dev/null | awk '/^  [a-z]+:/{print $1}'
}

# Manifest sources absent from the installed list passed on stdin.
missing_package_sources() {
  local installed manifest
  installed=$(mktemp)
  manifest=$(mktemp)
  cat > "$installed"
  manifest_package_sources > "$manifest"
  comm -23 <(sort -u "$manifest") <(sort -u "$installed")
  rm -f "$manifest" "$installed"
}

# Keep the current content of a target before it is overwritten. Works for
# files and directories; FORCE=1 skips it.
backup_target() {
  local target=$1 dest
  [ -e "$target" ] || return 0
  if [ "$FORCE" = 1 ]; then
    log "force: not backing up $target"
    return 0
  fi
  dest="$target.pre-restore.$STAMP"
  cp -a "$target" "$dest" || die "cannot back up $target"
  log "backed up $target -> $dest"
}

# True when the path or any ancestor below the home root is a symlink. Restore
# must not write through one: the link's target is outside the tracked tree.
path_crosses_symlink() {
  local p=$1
  while [ -n "$p" ] && [ "$p" != "/" ] && [ "$p" != "$HOST_HOME" ]; do
    [ -L "$p" ] && return 0
    p=$(dirname "$p")
  done
  return 1
}

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf 'would run: %s\n' "$*"
    return 0
  fi
  "$@"
}
