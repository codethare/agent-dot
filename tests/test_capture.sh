test_capture_sanitizes_and_copies() {
  make_fixture
  run_capture >/dev/null 2>&1
  assert_eq "0" "$?" "exit"
  assert_not_contains "$(cat "$FIX/repo/bootstrap/files/pi/settings.json")" "lastChangelogVersion"
  assert_eq "" "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['topic'])" "$FIX/repo/bootstrap/files/pi/pi-ntfy.json")" "topic blanked"
  assert_eq "export default 1" "$(cat "$FIX/repo/bootstrap/files/pi/extensions/a.ts")" "tree copied"
  assert_contains "$(git -C "$FIX/repo" status --short -- bootstrap)" "bootstrap/files" "changes left uncommitted without --commit"
}

test_capture_regenerates_pi_packages() {
  make_fixture
  run_capture >/dev/null 2>&1
  assert_contains "$(cat "$FIX/repo/bootstrap/manifests/pi-packages.json")" '"-index.ts"' "object entry keeps filters"
}

test_capture_regenerates_skills_manifest() {
  make_fixture
  run_capture >/dev/null 2>&1
  assert_eq "foo	https://example.com/foo.git" "$(cat "$FIX/repo/bootstrap/manifests/skills-repos.txt")" "skills manifest"
}

test_capture_warns_on_missing_source() {
  make_fixture
  err=$(run_capture 2>&1 >/dev/null); rc=$?
  assert_eq "0" "$rc" "missing sources are not fatal"
  assert_contains "$err" "missing source: .config/herdr/config.toml"
}

test_capture_refuses_unrelated_staged_changes() {
  make_fixture
  printf 'x\n' > "$FIX/repo/README.md"
  git -C "$FIX/repo" add README.md
  err=$(run_capture 2>&1 >/dev/null); rc=$?
  assert_eq "1" "$rc" "refuses"
  assert_contains "$err" "outside bootstrap/"
}

test_capture_leak_scan_blocks_commit() {
  make_fixture
  printf 'token ghp_%s\n' "0123456789012345678901234567890123" > "$FIX/home/.pi/agent/AGENTS.md"
  err=$(run_capture --commit 2>&1 >/dev/null); rc=$?
  assert_eq "1" "$rc" "leak is fatal"
  assert_contains "$err" "leak scan:"
  assert_contains "$err" "AGENTS.md"
  assert_eq "1" "$(git -C "$FIX/repo" log --oneline | wc -l | tr -d ' ')" "no commit"
}

test_capture_commit_creates_one_commit() {
  make_fixture
  run_capture --commit >/dev/null 2>&1
  assert_eq "0" "$?" "exit"
  assert_eq "chore(bootstrap): capture agent config" "$(git -C "$FIX/repo" log -1 --format=%s)" "subject"
  assert_eq "2" "$(git -C "$FIX/repo" log --oneline | wc -l | tr -d ' ')" "one new commit"
  assert_eq "" "$(grep -rl 'pi-secret' "$FIX/repo/bootstrap/files" 2>/dev/null)" "no topic in repo"
}
