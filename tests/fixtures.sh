# Shared fixtures for the bootstrap tests. Sourced by tests/run.sh.

# A sandbox home with the handful of real config files capture cares about,
# plus a throwaway git repo holding a copy of bootstrap/.
make_fixture() {
  FIX="$TMP/fix"
  rm -rf "$FIX"
  mkdir -p "$FIX/home/.pi/agent/extensions" "$FIX/home/skills/foo" "$FIX/repo"
  cp -a "$REPO/bootstrap" "$FIX/repo/bootstrap"
  # Start from an empty tracked set: the real repo ships captured config, which
  # would otherwise satisfy the assertions below.
  rm -rf "$FIX/repo/bootstrap/files" \
    "$FIX/repo/bootstrap/manifests/pi-packages.json" \
    "$FIX/repo/bootstrap/manifests/skills-repos.txt"
  git init -q "$FIX/repo"
  git -C "$FIX/repo" add bootstrap
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -q -m init
  printf '{"packages":["npm:a",{"source":"npm:b","extensions":["-index.ts"]}],"lastChangelogVersion":"9"}' > "$FIX/home/.pi/agent/settings.json"
  printf '{"topic":"pi-secret","server":"https://ntfy.sh"}' > "$FIX/home/.pi/agent/pi-ntfy.json"
  printf 'export default 1\n' > "$FIX/home/.pi/agent/extensions/a.ts"
  git init -q "$FIX/home/skills/foo"
  git -C "$FIX/home/skills/foo" remote add origin https://example.com/foo.git
  printf 'npm:a\nnpm:b\n' > "$FIX/pi-installed.txt"
}

# Create a placeholder for every mapped path the fixture does not already have,
# so capture and verify see a complete machine.
populate_home_from_map() {
  ( . "$REPO/bootstrap/lib.sh"
    map_entries | while IFS=$'\t' read -r _repo_rel home_rel kind; do
      p="$FIX/home/$home_rel"
      [ -e "$p" ] && continue
      if [ "$kind" = tree ]; then
        mkdir -p "$p"
        printf 'placeholder\n' > "$p/placeholder.txt"
      else
        mkdir -p "$(dirname "$p")"
        case $home_rel in
          *.json) printf '{"placeholder":true}\n' > "$p" ;;
          *) printf 'placeholder\n' > "$p" ;;
        esac
      fi
    done )
}

make_fake_tools() {
  mkdir -p "$FIX/bin"
  cat > "$FIX/bin/pi" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  list)
    if [ -n "${FAKE_PI_EXTRA:-}" ]; then printf '  %s\n' "$FAKE_PI_EXTRA"; fi
    sed 's/^/  /' "$FAKE_PI_INSTALLED" 2>/dev/null
    ;;
  --version) echo "pi 0.0.0" ;;
  *) : ;;
esac
SH
  cat > "$FIX/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_LOG:-/dev/null}"
if [ "${2:-}" = is-enabled ] && [ -n "${FAKE_TIMER_DISABLED:-}" ]; then exit 1; fi
exit 0
SH
  local tool
  for tool in bun mise herdr; do
    printf '#!/usr/bin/env bash\necho "%s fake 1.0"\n' "$tool" > "$FIX/bin/$tool"
  done
  chmod +x "$FIX/bin/pi" "$FIX/bin/systemctl" "$FIX/bin/bun" "$FIX/bin/mise" "$FIX/bin/herdr"
}

run_capture() { ( cd "$FIX/repo" && AGENT_BOOTSTRAP_HOME="$FIX/home" bash bootstrap/capture.sh "$@" ); }

run_verify() {
  ( cd "$FIX/repo" && \
    AGENT_BOOTSTRAP_HOME="$FIX/home" \
    PATH="$FIX/bin:$PATH" \
    FAKE_PI_INSTALLED="$FIX/pi-installed.txt" \
    FAKE_LOG="$FIX/log" \
    bash bootstrap/verify.sh "$@" )
}
