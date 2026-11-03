test_sanitize_settings_drops_volatile_keys() {
  printf '{"packages":["npm:a"],"extensions":["-builtin:mcp"],"lastChangelogVersion":"1.5.0","extensionChangelogVersions":{"x":"1"}}' > "$TMP/settings.json"
  python3 "$REPO/bootstrap/sanitize.py" .pi/agent/settings.json "$TMP/settings.json" "$TMP/out.json"
  assert_not_contains "$(cat "$TMP/out.json")" "lastChangelogVersion"
  assert_not_contains "$(cat "$TMP/out.json")" "extensionChangelogVersions"
  assert_contains "$(cat "$TMP/out.json")" '"-builtin:mcp"'
}

test_sanitize_ntfy_blanks_topic() {
  printf '{"topic":"pi-deadbeef","server":"https://ntfy.sh"}' > "$TMP/ntfy.json"
  python3 "$REPO/bootstrap/sanitize.py" .pi/agent/pi-ntfy.json "$TMP/ntfy.json" "$TMP/out.json"
  assert_eq "" "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['topic'])" "$TMP/out.json")"
  assert_eq "https://ntfy.sh" "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['server'])" "$TMP/out.json")"
}

test_sanitize_openspec_drops_anonymous_id() {
  printf '{"profile":"custom","telemetry":{"noticeSeen":true,"anonymousId":"1e03"}}' > "$TMP/oc.json"
  python3 "$REPO/bootstrap/sanitize.py" .config/openspec/config.json "$TMP/oc.json" "$TMP/out.json"
  assert_not_contains "$(cat "$TMP/out.json")" "anonymousId"
  assert_contains "$(cat "$TMP/out.json")" '"profile"'
}

test_sanitize_passthrough_is_byte_identical() {
  printf 'onboarding = false\n[terminal]\ndefault_shell = "fish"\n' > "$TMP/herdr.toml"
  python3 "$REPO/bootstrap/sanitize.py" .config/herdr/config.toml "$TMP/herdr.toml" "$TMP/out.toml"
  if cmp -s "$TMP/herdr.toml" "$TMP/out.toml"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: passthrough rewrite changed bytes"; fi
}

test_sanitized_hash_ignores_topic() {
  printf '{"topic":"one","server":"https://ntfy.sh"}' > "$TMP/a.json"
  printf '{"topic":"two","server":"https://ntfy.sh"}' > "$TMP/b.json"
  h1=$(python3 "$REPO/bootstrap/sanitize.py" --hash .pi/agent/pi-ntfy.json "$TMP/a.json")
  h2=$(python3 "$REPO/bootstrap/sanitize.py" --hash .pi/agent/pi-ntfy.json "$TMP/b.json")
  assert_eq "$h1" "$h2" "topic redacted"
  if printf '%s' "$h1" | grep -Eq '^[0-9a-f]{64}$'; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: hash is not sha256 hex: [$h1]"; fi
}
