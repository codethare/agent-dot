# Install fixtures: run every install test against a sandbox HOME with fakes
# for the tools install.sh shells out to.

make_install_bin() {
  mkdir -p "$FIX/bin"
  cp "$REPO/tests/fixtures/fake-pi" "$FIX/bin/pi"
  chmod +x "$FIX/bin/pi"
  local tool
  for tool in bun mise herdr; do
    cat > "$FIX/bin/$tool" <<SH
#!/usr/bin/env bash
[ -n "\${FAKE_LOG:-}" ] && printf '$tool %s\n' "\$*" >> "\$FAKE_LOG"
case "\${1:-}" in
  --version) echo "$tool fake 1.0" ;;
esac
exit 0
SH
    chmod +x "$FIX/bin/$tool"
  done
  cat > "$FIX/bin/sudo" <<'SH'
#!/usr/bin/env bash
exec "$@"
SH
  cat > "$FIX/bin/pacman" <<'SH'
#!/usr/bin/env bash
[ -n "${FAKE_LOG:-}" ] && printf 'pacman %s\n' "$*" >> "$FAKE_LOG"
cat >/dev/null
SH
  cat > "$FIX/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${FAKE_LOG:-/dev/null}"
if [ "${2:-}" = is-enabled ] && [ -n "${FAKE_TIMER_DISABLED:-}" ]; then exit 1; fi
exit 0
SH
  cat > "$FIX/bin/id" <<'SH'
#!/usr/bin/env bash
if [ -n "${FAKE_ROOT:-}" ] && [ "${1:-}" = -u ]; then echo 0; exit 0; fi
exec /usr/bin/id "$@"
SH
  chmod +x "$FIX/bin/sudo" "$FIX/bin/pacman" "$FIX/bin/systemctl" "$FIX/bin/id"
}

# Capture a complete repo from the fixture home, then hand install an empty
# home so every restore is observable.
prepare_install() {
  make_fixture
  populate_home_from_map
  make_fake_tools
  run_capture >/dev/null 2>&1
  rm -rf "$FIX/home"
  mkdir -p "$FIX/home"
  rm -rf "$FIX/bin"
  make_install_bin
  : > "$FIX/pi-state.txt"
  : > "$FIX/log"
}

run_install() {
  ( cd "$FIX/repo" && \
    AGENT_BOOTSTRAP_HOME="$FIX/home" \
    PATH="$FIX/bin:$PATH" \
    FAKE_STATE="$FIX/pi-state.txt" \
    FAKE_SETTINGS="$FIX/home/.pi/agent/settings.json" \
    FAKE_LOG="$FIX/log" \
    FAKE_INSTALL_NOOP="${FAKE_INSTALL_NOOP:-}" \
    bash bootstrap/install.sh "$@" )
}

test_install_dry_run_changes_nothing() {
  prepare_install
  out=$(run_install --dry-run 2>&1); rc=$?
  assert_eq "0" "$rc" "dry run exit"
  assert_contains "$out" "would run:"
  assert_eq "0" "$(find "$FIX/home" -mindepth 1 | wc -l | tr -d ' ')" "nothing written"
}

test_install_prepends_bun_and_mise_paths() {
  prepare_install
  run_install --only report >/dev/null 2>&1
  log=$(cat "$FIX/log")
  assert_contains "$log" "PATH=$FIX/home/.bun/bin"
  assert_contains "$log" "$FIX/home/.local/share/mise/shims"
  assert_contains "$log" "PI_CODING_AGENT_DIR=$FIX/home/.pi/agent"
}

test_install_backs_up_existing_file() {
  prepare_install
  mkdir -p "$FIX/home/.pi/agent"
  printf '{"old":true}\n' > "$FIX/home/.pi/agent/settings.json"
  run_install --only pifiles >/dev/null 2>&1
  assert_eq "0" "$?" "exit"
  assert_eq '{"old":true}' "$(cat "$FIX"/home/.pi/agent/settings.json.pre-restore.*)" "backup content"
  assert_eq "$(cat "$FIX/repo/bootstrap/files/pi/settings.json")" "$(cat "$FIX/home/.pi/agent/settings.json")" "settings restored"
}

test_install_restores_empty_ntfy_topic() {
  prepare_install
  run_install --only pifiles >/dev/null 2>&1
  assert_eq "" "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['topic'])" "$FIX/home/.pi/agent/pi-ntfy.json")" "topic blank"
}

test_install_chmods_skills_pull() {
  prepare_install
  run_install --only pifiles >/dev/null 2>&1
  assert_eq "755" "$(stat -c %a "$FIX/home/.local/bin/skills-pull")" "exec bit"
}

test_install_pipackages_falls_back_and_keeps_filters() {
  prepare_install
  run_install --only pipackages >/dev/null 2>&1
  assert_eq "0" "$?" "exit"
  assert_contains "$(cat "$FIX/log")" "pi install npm:a"
  assert_contains "$(cat "$FIX/log")" "pi install npm:b"
  assert_eq "1" "$(python3 - "$FIX/home/.pi/agent/settings.json" <<'PY'
import json, sys
obj = json.load(open(sys.argv[1]))
print(sum(1 for e in obj["packages"] if isinstance(e, dict) and e.get("extensions") == ["-index.ts"]))
PY
)" "object entry with filters survives"
}

test_install_fails_when_package_stays_missing() {
  prepare_install
  out=$(FAKE_INSTALL_NOOP=1 run_install --only pipackages 2>&1); rc=$?
  assert_eq "1" "$rc" "exit"
  assert_contains "$out" "packages missing after install"
}

test_install_skips_existing_skills_dir() {
  prepare_install
  mkdir -p "$FIX/home/skills/foo"
  printf 'marker\n' > "$FIX/home/skills/foo/marker"
  run_install --only skills >/dev/null 2>&1
  assert_eq "marker" "$(cat "$FIX/home/skills/foo/marker")" "existing repo untouched"
  assert_eq "1" "$(ls -A "$FIX/home/skills/foo" | wc -l | tr -d ' ')" "nothing cloned into it"
}

test_install_enables_timer() {
  prepare_install
  run_install --only timer >/dev/null 2>&1
  assert_contains "$(cat "$FIX/log")" "systemctl --user enable --now skills-pull.timer"
}

test_install_refuses_root() {
  prepare_install
  out=$(FAKE_ROOT=1 run_install --only preflight 2>&1); rc=$?
  assert_eq "1" "$rc" "exit"
  assert_contains "$out" "do not run as root"
}
