test_map_entries_has_19_unique_paths() {
  . "$REPO/bootstrap/lib.sh"
  assert_eq "19" "$(map_entries | wc -l | tr -d ' ')" "row count"
  assert_eq "19" "$(map_entries | cut -f2 | sort -u | wc -l | tr -d ' ')" "unique home paths"
  assert_eq "3" "$(map_entries | awk -F'\t' '$3=="tree"' | wc -l | tr -d ' ')" "tree entries"
}

test_map_entries_home_paths_are_relative() {
  . "$REPO/bootstrap/lib.sh"
  if map_entries | cut -f2 | grep -q '^/'; then FAIL=$((FAIL+1)); echo "FAIL: absolute home path in map"; else PASS=$((PASS+1)); fi
}

test_host_path_joins_home() {
  . "$REPO/bootstrap/lib.sh"
  HOST_HOME=/sandbox
  assert_eq "/sandbox/.pi/agent/settings.json" "$(host_path .pi/agent/settings.json)" "host_path"
  assert_eq "0755" "$(entry_mode .local/bin/skills-pull)" "exec mode"
  assert_eq "0644" "$(entry_mode .pi/agent/settings.json)" "default mode"
}

test_backup_target_copies_content_and_keeps_original() {
  . "$REPO/bootstrap/lib.sh"
  printf 'old\n' > "$TMP/settings.json"
  backup_target "$TMP/settings.json" >/dev/null
  assert_eq "old" "$(cat "$TMP/settings.json")" "original intact"
  assert_eq "1" "$(ls "$TMP"/settings.json.pre-restore.* | wc -l | tr -d ' ')" "one backup"
  assert_eq "old" "$(cat "$TMP"/settings.json.pre-restore.*)" "backup content"
}

test_backup_target_skips_when_forced() {
  . "$REPO/bootstrap/lib.sh"; FORCE=1
  printf 'old\n' > "$TMP/f.json"
  backup_target "$TMP/f.json" >/dev/null
  if ls "$TMP"/f.json.pre-restore.* >/dev/null 2>&1; then FAIL=$((FAIL+1)); echo "FAIL: backup written despite FORCE"; else PASS=$((PASS+1)); fi
}

test_run_respects_dry_run() {
  . "$REPO/bootstrap/lib.sh"; DRY_RUN=1
  assert_contains "$(run touch "$TMP/should-not-exist")" "would run"
  if [ -e "$TMP/should-not-exist" ]; then FAIL=$((FAIL+1)); echo "FAIL: dry run created a file"; else PASS=$((PASS+1)); fi
}

test_missing_package_sources_diffs_manifest_and_install() {
  mkdir -p "$TMP/manifests"
  printf '["npm:a",{"source":"npm:b","extensions":["-index.ts"]}]\n' > "$TMP/manifests/pi-packages.json"
  . "$REPO/bootstrap/lib.sh"
  MANIFESTS_DIR="$TMP/manifests"
  assert_eq "npm:b" "$(missing_package_sources <<<'npm:a')" "missing list"
  assert_eq "npm:a npm:b" "$(manifest_package_sources | tr '\n' ' ' | sed 's/ $//')" "manifest sources"
}

test_die_exits_one_with_message() {
  out=$(bash -c "source '$REPO/bootstrap/lib.sh'; die boom" 2>&1); rc=$?
  assert_eq "1" "$rc" "exit code"
  assert_contains "$out" "boom"
}
