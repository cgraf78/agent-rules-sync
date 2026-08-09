#!/usr/bin/env bash
# Repository-owned test harness for the public provider contract.

PASS=0
FAIL=0

# A caller's XDG roots must never make a synthetic test write into the real
# installation. Individual assertions opt back into fixture-local roots.
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME

_pass() {
  PASS=$((PASS + 1))
  printf '  PASS: %s\n' "$1"
}

_fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL: %s\n' "$1" >&2
}

_assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    _pass "$desc"
  else
    _fail "$desc (expected '$expected', got '$actual')"
  fi
}

_assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    _pass "$desc"
  else
    _fail "$desc (expected to contain '$expected')"
  fi
}

_assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if [[ "$actual" != *"$unexpected"* ]]; then
    _pass "$desc"
  else
    _fail "$desc (should not contain '$unexpected')"
  fi
}

_assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    _pass "$desc"
  else
    _fail "$desc (expected exit $expected, got $actual)"
  fi
}

_assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    _pass "$desc"
  else
    _fail "$desc (file not found: $path)"
  fi
}

_assert_file_missing() {
  local desc="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    _pass "$desc"
  else
    _fail "$desc (file should not exist: $path)"
  fi
}

_assert_path_missing() {
  local desc="$1" path="$2"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    _pass "$desc"
  else
    _fail "$desc (path should not exist: $path)"
  fi
}

_assert_file_content() {
  local desc="$1" expected="$2" path="$3" actual
  if [[ ! -f "$path" ]]; then
    _fail "$desc (file not found: $path)"
    return
  fi
  actual=$(<"$path")
  _assert_eq "$desc" "$expected" "$actual"
}

_assert_mode() {
  local desc="$1" expected="$2" path="$3" actual
  if actual=$(stat -c '%a' "$path" 2>/dev/null); then
    :
  elif actual=$(stat -f '%Lp' "$path" 2>/dev/null); then
    :
  else
    _fail "$desc (could not read mode: $path)"
    return
  fi
  _assert_eq "$desc" "$expected" "$actual"
}

_AGENT_RULES_TEST_ROOT=$(mktemp -d \
  "${TMPDIR:-/tmp}/agent-rules-sync-test.XXXXXXXX") || {
  printf 'agent-rules-sync test: could not create temporary root\n' >&2
  exit 1
}
case "$_AGENT_RULES_TEST_ROOT" in
  "${TMPDIR:-/tmp}"/agent-rules-sync-test.*) ;;
  *)
    printf 'agent-rules-sync test: unsafe temporary root: %s\n' \
      "$_AGENT_RULES_TEST_ROOT" >&2
    exit 1
    ;;
esac
[[ -d "$_AGENT_RULES_TEST_ROOT" ]] || exit 1

_agent_rules_test_cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$_AGENT_RULES_TEST_ROOT"
  exit "$status"
}
trap _agent_rules_test_cleanup EXIT

_tmpdir() {
  local path
  path=$(mktemp -d "$_AGENT_RULES_TEST_ROOT/suite.XXXXXXXX") || return 1
  case "$path" in
    "$_AGENT_RULES_TEST_ROOT"/*) ;;
    *)
      printf 'agent-rules-sync test: unsafe suite directory: %s\n' "$path" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$path"
}

_test_summary() {
  printf '\n================================\n'
  printf 'Results: %s passed, %s failed\n' "$PASS" "$FAIL"
  printf '================================\n'
  [[ "$FAIL" -eq 0 ]] && exit 0
  exit 1
}
