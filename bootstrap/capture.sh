#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=bootstrap/lib.sh
. "$HERE/lib.sh"

usage() {
  cat <<'EOF'
Usage: bootstrap/capture.sh [--commit]

Copy the mapped agent config from this machine into bootstrap/files, regenerate
the generated manifests, scan for leaks, and optionally commit the result.
Without --commit the changes are left in the working tree for review.
EOF
}

COMMIT=0
while [ $# -gt 0 ]; do
  case $1 in
    --commit) COMMIT=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

cd "$REPO_ROOT"

# Capture is about bootstrap/ only; unrelated staged work would ride along in
# the capture commit.
if [ -n "$(git diff --cached --name-only | grep -v '^bootstrap/' || true)" ]; then
  die "staged changes outside bootstrap/; commit or unstage them first"
fi

mkdir -p "$FILES_DIR" "$MANIFESTS_DIR"

while IFS=$'\t' read -r repo_rel home_rel kind; do
  src=$(host_path "$home_rel")
  dest=$(repo_path "$repo_rel")
  if [ ! -e "$src" ]; then
    warn "missing source: $home_rel (skipped)"
    continue
  fi
  mkdir -p "$(dirname "$dest")"
  if [ "$kind" = tree ]; then
    case $dest in
      "$FILES_DIR"/*) ;;
      *) die "refusing to remove path outside bootstrap/files: $dest" ;;
    esac
    rm -rf "$dest"
    cp -a "$src" "$dest"
  else
    sanitize_copy "$home_rel" "$src" "$dest"
  fi
done < <(map_entries)

# Pi's package list is generated from the captured settings so it cannot drift
# from what Pi itself reads.
regenerate_pi_packages() {
  local settings="$FILES_DIR/pi/settings.json"
  if [ ! -f "$settings" ]; then
    warn "no settings.json captured; leaving pi-packages.json untouched"
    return 0
  fi
  python3 - "$settings" "$MANIFESTS_DIR/pi-packages.json" <<'PY'
import json
import sys

source, dest = sys.argv[1], sys.argv[2]
packages = json.load(open(source)).get("packages", [])
with open(dest, "w") as out:
    json.dump(packages, out, ensure_ascii=False, indent=2)
    out.write("\n")
PY
}

# Skill repos are recorded by remote, not by content: they are clones.
regenerate_skills_repos() {
  local dir url name
  for dir in "$HOST_HOME"/skills/*/; do
    [ -d "$dir/.git" ] || continue
    name=$(basename "$dir")
    if url=$(git -C "$dir" remote get-url origin 2>/dev/null); then
      printf '%s\t%s\n' "$name" "$url"
    else
      warn "skills repo without origin: $name (skipped)"
    fi
  done | sort > "$MANIFESTS_DIR/skills-repos.txt"
}

leak_scan() {
  local hits
  hits=$(grep -RInEf "$BOOTSTRAP_DIR/leak-patterns.txt" "$BOOTSTRAP_DIR" \
    --exclude-dir=.git 2>/dev/null | sed 's|^|leak scan: |' || true)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" >&2
    die "leak scan matched; nothing committed"
  fi
}

regenerate_pi_packages
regenerate_skills_repos
leak_scan

if [ -n "$(git status --porcelain -- bootstrap)" ]; then
  git status --short -- bootstrap
else
  log "nothing to capture"
fi

if [ "$COMMIT" = 1 ]; then
  git add bootstrap
  if git diff --cached --quiet; then
    log "nothing staged; no commit"
  else
    git commit -q -m "chore(bootstrap): capture agent config"
    git --no-pager log --oneline -1
  fi
else
  log "review the changes above, then run with --commit to record them"
fi
