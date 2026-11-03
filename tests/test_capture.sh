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

test_capture_skips_skill_dir_without_remote() {
  make_fixture
  git -C "$FIX/home/skills/foo" remote remove origin
  mkdir -p "$FIX/home/skills/bar"
  git init -q "$FIX/home/skills/bar"
  err=$(run_capture 2>&1 >/dev/null); rc=$?
  assert_eq "0" "$rc" "not fatal"
  assert_not_contains "$(cat "$FIX/repo/bootstrap/manifests/skills-repos.txt" 2>/dev/null)" "bar"
  assert_contains "$err" "without origin"
}

test_capture_keeps_manifest_when_skills_absent() {
  make_fixture
  printf 'keep\thttps://example.com/keep.git\n' > "$FIX/repo/bootstrap/manifests/skills-repos.txt"
  rm -rf "$FIX/home/skills"
  run_capture >/dev/null 2>&1
  assert_contains "$(cat "$FIX/repo/bootstrap/manifests/skills-repos.txt")" "keep"
}

test_capture_skips_symlinked_tree() {
  make_fixture
  mv "$FIX/home/.pi/agent/extensions" "$FIX/home/ext-real"
  ln -s "$FIX/home/ext-real" "$FIX/home/.pi/agent/extensions"
  err=$(run_capture 2>&1 >/dev/null); rc=$?
  assert_eq "0" "$rc" "not fatal"
  assert_contains "$err" "symlink"
  if [ -e "$FIX/repo/bootstrap/files/pi/extensions" ]; then
    FAIL=$((FAIL+1)); echo "FAIL: captured a symlinked tree"
  else PASS=$((PASS+1)); fi
}

test_capture_leak_scan_blocks_lowercase_key() {
  make_fixture
  mkdir -p "$FIX/home/.config/ponytail"
  printf '{"apiKey":"abcdefghijkl"}\n' > "$FIX/home/.config/ponytail/config.json"
  err=$(run_capture --commit 2>&1 >/dev/null); rc=$?
  assert_eq "1" "$rc" "lowercase key caught"
  assert_contains "$err" "leak scan:"
}

test_capture_leak_scan_blocks_absolute_home_path() {
  make_fixture
  printf 'see /home/otheruser/notes\n' > "$FIX/home/.pi/agent/AGENTS.md"
  err=$(run_capture --commit 2>&1 >/dev/null); rc=$?
  assert_eq "1" "$rc" "absolute home path caught"
  assert_contains "$err" "leak scan:"
}
