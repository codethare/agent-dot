test_verify_clean_exits_zero() {
  make_fixture; populate_home_from_map; make_fake_tools
  run_capture >/dev/null 2>&1
  assert_eq "0" "$?" "capture"
  out=$(run_verify 2>&1); rc=$?
  assert_eq "0" "$rc" "clean machine"
  assert_not_contains "$out" "modified:"
  assert_not_contains "$out" "missing:"
  assert_not_contains "$out" "extra:"
}

test_verify_reports_modified_file() {
  make_fixture; populate_home_from_map; make_fake_tools
  run_capture >/dev/null 2>&1
  python3 - "$FIX/home/.pi/agent/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
obj = json.load(open(p))
obj["defaultModel"] = "changed/model"
json.dump(obj, open(p, "w"), indent=2)
PY
  out=$(run_verify 2>&1); rc=$?
  assert_eq "1" "$rc" "drift exit"
  assert_contains "$out" "modified: .pi/agent/settings.json"
}

test_verify_ignores_volatile_settings_keys() {
  make_fixture; populate_home_from_map; make_fake_tools
  run_capture >/dev/null 2>&1
  python3 - "$FIX/home/.pi/agent/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
obj = json.load(open(p))
obj["lastChangelogVersion"] = "9.9.9"
obj["extensionChangelogVersions"] = {"x": "1"}
json.dump(obj, open(p, "w"), indent=2)
PY
  out=$(run_verify 2>&1); rc=$?
  assert_eq "0" "$rc" "volatile keys ignored"
  assert_not_contains "$out" "modified:"
}

test_verify_ignores_ntfy_topic_change() {
  make_fixture; populate_home_from_map; make_fake_tools
  run_capture >/dev/null 2>&1
  printf '{"topic":"pi-new-topic","server":"https://ntfy.sh"}\n' > "$FIX/home/.pi/agent/pi-ntfy.json"
  out=$(run_verify 2>&1); rc=$?
  assert_eq "0" "$rc" "topic drift ignored"
}

test_verify_reports_missing_source() {
  make_fixture; populate_home_from_map; make_fake_tools
  run_capture >/dev/null 2>&1
  rm "$FIX/home/.config/ponytail/config.json"
  out=$(run_verify 2>&1); rc=$?
  assert_eq "1" "$rc" "drift exit"
  assert_contains "$out" "missing: .config/ponytail/config.json"
}

test_verify_reports_unmanaged_package() {
  make_fixture; populate_home_from_map; make_fake_tools
  run_capture >/dev/null 2>&1
  out=$(FAKE_PI_EXTRA=npm:zzz bash -c "cd '$FIX/repo' && AGENT_BOOTSTRAP_HOME='$FIX/home' PATH='$FIX/bin:$PATH' FAKE_PI_INSTALLED='$FIX/pi-installed.txt' FAKE_PI_EXTRA=npm:zzz bash bootstrap/verify.sh" 2>&1); rc=$?
  assert_eq "1" "$rc" "drift exit"
  assert_contains "$out" "unmanaged package: npm:zzz"
}

test_verify_reports_disabled_timer() {
  make_fixture; populate_home_from_map; make_fake_tools
  run_capture >/dev/null 2>&1
  out=$(FAKE_TIMER_DISABLED=1 bash -c "cd '$FIX/repo' && AGENT_BOOTSTRAP_HOME='$FIX/home' PATH='$FIX/bin:$PATH' FAKE_PI_INSTALLED='$FIX/pi-installed.txt' FAKE_TIMER_DISABLED=1 bash bootstrap/verify.sh" 2>&1); rc=$?
  assert_eq "1" "$rc" "drift exit"
  assert_contains "$out" "drift: timer not enabled"
}

test_verify_reports_missing_tool() {
  make_fixture; populate_home_from_map; make_fake_tools
  run_capture >/dev/null 2>&1
  rm "$FIX/bin/herdr"
  # Isolate PATH from the machine's mise shims so herdr is genuinely absent.
  out=$(cd "$FIX/repo" && AGENT_BOOTSTRAP_HOME="$FIX/home" PATH="$FIX/bin:/usr/bin:/bin" \
    FAKE_PI_INSTALLED="$FIX/pi-installed.txt" bash bootstrap/verify.sh 2>&1); rc=$?
  assert_eq "1" "$rc" "missing tool is drift"
  assert_contains "$out" "missing tool: herdr"
}
