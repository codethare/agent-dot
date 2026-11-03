#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Tools installed by this script land in directories a fresh bash does not
# have on PATH. Add them for this process only; shell config stays in ~/.dot/dot.
# Use the same home root lib.sh will resolve, so a sandboxed run cannot pick up
# the real user's tools.
HOME_ROOT=${AGENT_BOOTSTRAP_HOME:-$HOME}
PATH="$HOME_ROOT/.bun/bin:$HOME_ROOT/.local/bin:$HOME_ROOT/.local/share/mise/shims:$PATH"
export PATH

# shellcheck source=bootstrap/lib.sh
. "$HERE/lib.sh"

# Pi reads and writes the agent dir this script restores into, so a sandboxed
# run cannot touch the real user's config.
export PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOST_HOME/.pi/agent}"

STEPS=(preflight packages mise bunglobals pifiles pipackages skills timer report)
ONLY=""

usage() {
  cat <<'EOF'
Usage: bootstrap/install.sh [--dry-run] [--force] [--only <steps>]

Rebuild the agent environment from this repo. Steps run in order:
  preflight packages mise bunglobals pifiles pipackages skills timer report

  --dry-run       print what would run, change nothing
  --force         overwrite targets without <target>.pre-restore.<stamp> copies
  --only a,b      run only the named steps
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --only) shift; ONLY=${1:-} ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

step_preflight() {
  require git
  require python3
  [ "$(id -u)" -ne 0 ] || die "do not run as root"
  if ! grep -q '^ID=arch' /etc/os-release 2>/dev/null; then
    warn "this is not Arch Linux; the packages step may not apply"
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsS -m 5 -o /dev/null https://registry.npmjs.org/ 2>/dev/null ||
      warn "npm registry unreachable; package steps will fail"
  else
    warn "curl not found; skipping the network check"
  fi
  log "preflight ok in $HOST_HOME"
}

step_packages() {
  if ! command -v pacman >/dev/null 2>&1; then
    warn "pacman not found; install these packages yourself: $(tr '\n' ' ' < "$MANIFESTS_DIR/pacman.txt")"
    return 0
  fi
  local sudo_cmd=()
  if [ "$(id -u)" -ne 0 ]; then
    require sudo
    sudo_cmd=(sudo)
  fi
  if [ "$DRY_RUN" = 1 ]; then
    printf 'would run: %s pacman -S --needed - < %s\n' "${sudo_cmd[*]:-}" "$MANIFESTS_DIR/pacman.txt"
    return 0
  fi
  "${sudo_cmd[@]}" pacman -S --needed - < "$MANIFESTS_DIR/pacman.txt"
}

step_mise() {
  require mise
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    run mise use -g "$line"
  done < "$MANIFESTS_DIR/mise-tools.txt"
  run mise install
}

step_bunglobals() {
  require bun
  local pkg
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    run bun add -g "$pkg"
  done < "$MANIFESTS_DIR/bun-globals.txt"
}

step_pifiles() {
  while IFS=$'\t' read -r repo_rel home_rel kind; do
    src=$(repo_path "$repo_rel")
    dest=$(host_path "$home_rel")
    if [ ! -e "$src" ]; then
      warn "not in repo: $repo_rel (skipped)"
      continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
      [ -e "$dest" ] && printf 'would run: backup %s\n' "$dest"
      printf 'would copy: %s -> %s\n' "$src" "$dest"
      continue
    fi
    backup_target "$dest"
    mkdir -p "$(dirname "$dest")"
    if [ "$kind" = tree ]; then
      case $dest in
        "$HOST_HOME"/*) rm -rf "$dest" ;;
        *) die "refusing to remove path outside home: $dest" ;;
      esac
      cp -a "$src" "$dest"
    else
      cp "$src" "$dest"
      chmod "$(entry_mode "$home_rel")" "$dest"
    fi
  done < <(map_entries)
}

step_pipackages() {
  require pi
  if [ "$DRY_RUN" = 1 ]; then
    printf 'would run: pi update --extensions\n'
    return 0
  fi
  pi update --extensions || warn "pi update --extensions reported a failure; checking what is installed"
  local missing
  missing=$(installed_package_sources | missing_package_sources || true)
  if [ -n "$missing" ]; then
    local source
    for source in $missing; do
      log "installing missing package: $source"
      pi install "$source" || die "pi install $source failed"
    done
    # `pi install` rewrites the entry as a plain string, which drops the
    # extension filters object entries carry; restore the tracked settings.
    mkdir -p "$(dirname "$(host_path .pi/agent/settings.json)")"
    cp "$(repo_path pi/settings.json)" "$(host_path .pi/agent/settings.json)"
    pi update --extensions || warn "pi update --extensions failed after the fallback"
    missing=$(installed_package_sources | missing_package_sources || true)
  fi
  [ -z "$missing" ] || die "packages missing after install: $(echo $missing)"
}

step_skills() {
  if [ ! -f "$MANIFESTS_DIR/skills-repos.txt" ]; then
    warn "no skills manifest; skipping"
    return 0
  fi
  local name url dir
  while IFS=$'\t' read -r name url; do
    [ -n "$name" ] || continue
    dir="$HOST_HOME/skills/$name"
    if [ -d "$dir" ]; then
      log "skills repo present: $name"
      continue
    fi
    run git clone "$url" "$dir"
  done < "$MANIFESTS_DIR/skills-repos.txt"
}

step_timer() {
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl not found; skipping the skills-pull timer"
    return 0
  fi
  run systemctl --user daemon-reload
  run systemctl --user enable --now skills-pull.timer
}

step_report() {
  if [ -f "$BOOTSTRAP_DIR/secrets.checklist.md" ]; then
    cat "$BOOTSTRAP_DIR/secrets.checklist.md"
  else
    warn "secrets.checklist.md is missing"
  fi

  local missing
  missing=$(installed_package_sources 2>/dev/null | missing_package_sources || true)
  [ -z "$missing" ] || warn "packages still missing: $(echo $missing)"

  if [ -f "$MANIFESTS_DIR/skills-repos.txt" ]; then
    local name url
    while IFS=$'\t' read -r name url; do
      [ -n "$name" ] || continue
      [ -d "$HOST_HOME/skills/$name" ] || warn "skills repo missing: $name"
    done < "$MANIFESTS_DIR/skills-repos.txt"
  fi

  local tool
  for tool in git pi bun mise herdr; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf '%-6s %s\n' "$tool" "$("$tool" --version 2>/dev/null | head -1)"
    else
      warn "missing tool: $tool"
    fi
  done

  log "manual: start pi and send one message (needs the key from the checklist)"
}

selected() {
  local step=$1
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in
    *",$step,"*) return 0 ;;
  esac
  return 1
}

if [ -n "$ONLY" ]; then
  for entry in ${ONLY//,/ }; do
    case " ${STEPS[*]} " in
      *" $entry "*) ;;
      *) die "unknown step: $entry (known: ${STEPS[*]})" ;;
    esac
  done
fi

for step in "${STEPS[@]}"; do
  selected "$step" || continue
  log "step: $step"
  "step_$step"
done

log "install finished"
