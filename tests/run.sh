#!/usr/bin/env bash
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert_eq() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: expected [$2], got [$1] (${3:-})"; fi; }
assert_contains() { case "$1" in *"$2"*) PASS=$((PASS+1));; *) FAIL=$((FAIL+1)); echo "FAIL: missing [$2] in [$1]";; esac; }
assert_not_contains() { case "$1" in *"$2"*) FAIL=$((FAIL+1)); echo "FAIL: unexpected [$2] in [$1]";; *) PASS=$((PASS+1));; esac; }
assert_exit() { local want=$1; shift; "$@"; local got=$?; assert_eq "$got" "$want" "exit of $*"; }

for f in "$REPO"/tests/test_*.sh; do . "$f"; done
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  before=$FAIL; $t; [ "$before" -eq "$FAIL" ] && echo "ok   $t"
done
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
