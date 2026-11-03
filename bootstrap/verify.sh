#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=bootstrap/lib.sh
. "$HERE/lib.sh"

usage() {
  cat <<'EOF'
Usage: bootstrap/verify.sh

Compare this machine against the tracked config. Prints one line per
difference and exits 1 when any exist, 0 when the two agree.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

drift=0
note() { printf '%s\n' "$*"; drift=1; }

# Tracked files and trees. Files are compared after sanitizing, so the two
# volatile settings keys and the ntfy topic never count as drift.
while IFS=$'\t' read -r repo_rel home_rel kind; do
  src=$(host_path "$home_rel")
  repo=$(repo_path "$repo_rel")
  if [ ! -e "$src" ]; then
    note "missing: $home_rel"
    continue
  fi
  if [ ! -e "$repo" ]; then
    note "untracked: $home_rel"
    continue
  fi
  if [ "$kind" = tree ]; then
    while IFS= read -r file; do
      rel=${file#"$src"/}
      if [ ! -e "$repo/$rel" ]; then
        note "untracked: $home_rel/$rel"
      elif ! cmp -s "$file" "$repo/$rel"; then
        note "modified: $home_rel/$rel"
      fi
    done < <(find "$src" -type f)
    while IFS= read -r file; do
      rel=${file#"$repo"/}
      [ -e "$src/$rel" ] || note "extra: $home_rel/$rel"
    done < <(find "$repo" -type f)
  elif [ "$(sanitized_hash "$home_rel" "$src")" != "$(sanitized_hash "$home_rel" "$repo")" ]; then
    note "modified: $home_rel"
  fi
done < <(map_entries)

# Package set: the manifest is the truth, Pi is the machine.
if [ -f "$MANIFESTS_DIR/pi-packages.json" ]; then
  installed=$(installed_package_sources || true)
  missing=$(printf '%s\n' "$installed" | missing_package_sources || true)
  for source in $missing; do
    note "missing package: $source"
  done
  installed_sorted=$(mktemp)
  manifest_sorted=$(mktemp)
  printf '%s\n' "$installed" | sed '/^$/d' | sort -u > "$installed_sorted"
  manifest_package_sources | sort -u > "$manifest_sorted"
  for source in $(comm -13 "$manifest_sorted" "$installed_sorted" || true); do
    note "unmanaged package: $source"
  done
  rm -f "$installed_sorted" "$manifest_sorted"
fi

if [ -f "$MANIFESTS_DIR/skills-repos.txt" ]; then
  while IFS=$'\t' read -r name url; do
    [ -n "$name" ] || continue
    dir="$HOST_HOME/skills/$name"
    if [ ! -d "$dir" ]; then
      note "missing skills repo: $name"
      continue
    fi
    actual=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
    [ "$actual" = "$url" ] || note "skills repo remote differs: $name ($actual)"
  done < "$MANIFESTS_DIR/skills-repos.txt"
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user is-enabled skills-pull.timer >/dev/null 2>&1 ||
    note "drift: timer not enabled"
else
  warn "systemctl not found; skipping the timer check"
fi

for tool in pi bun mise herdr; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%-6s %s\n' "$tool" "$("$tool" --version 2>/dev/null | head -1)"
  else
    note "missing tool: $tool"
  fi
done

if [ "$drift" -eq 0 ]; then
  log "machine matches tracked config"
fi
[ "$drift" -eq 0 ]
