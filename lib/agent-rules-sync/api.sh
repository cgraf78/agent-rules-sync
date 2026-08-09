# shellcheck shell=bash
# Public provider operations.

_agent_rules_lib_dir=$(cd "${BASH_SOURCE[0]%/*}" && pwd -P) || return 1
# shellcheck source=paths.sh
. "$_agent_rules_lib_dir/paths.sh"
# shellcheck source=temp.sh
. "$_agent_rules_lib_dir/temp.sh"
# shellcheck source=manifest.sh
. "$_agent_rules_lib_dir/manifest.sh"
# shellcheck source=render.sh
. "$_agent_rules_lib_dir/render.sh"
# shellcheck source=managed.sh
. "$_agent_rules_lib_dir/managed.sh"
# shellcheck source=targets.sh
. "$_agent_rules_lib_dir/targets.sh"
# shellcheck source=lock.sh
. "$_agent_rules_lib_dir/lock.sh"
# shellcheck source=migration.sh
. "$_agent_rules_lib_dir/migration.sh"

_agent_rules_sync_locked() {
  local block target
  _agent_rules_load_previous || return 1

  block=$(_agent_rules_managed_block) || return 1
  for target in "${_AGENT_RULES_TARGET_PATHS[@]+"${_AGENT_RULES_TARGET_PATHS[@]}"}"; do
    if ((${#_AGENT_RULES_RULE_FILES[@]} == 0)); then
      _agent_rules_prune_target "$target" || return 1
    else
      _agent_rules_publish_target "$target" "$block" || return 1
    fi
  done
  _agent_rules_prune_stale || return 1
  _agent_rules_write_state || {
    _agent_rules_error "could not write target inventory"
    return 1
  }
  _agent_rules_consume_legacy_state || return 1
}

agent_rules_sync() {
  local manifest="$1" status
  _agent_rules_validate_runtime_paths || return 1
  _agent_rules_parse_manifest "$manifest" || return 1
  _agent_rules_render || return 1
  _agent_rules_collect_targets || return 1
  _agent_rules_validate_target_collisions || return 1
  _agent_rules_acquire_lock || return 1
  _agent_rules_sync_locked
  status=$?
  _agent_rules_release_lock || status=1
  return "$status"
}

_agent_rules_uninstall_locked() {
  local target agent
  _agent_rules_load_previous || return 1

  # Known built-ins remain discoverable even if the inventory was manually
  # removed. Custom targets are intentionally touched only when recorded.
  for agent in claude codex gemini opencode; do
    target=$(_agent_rules_builtin_target "$agent") || return 1
    _agent_rules_add_previous_target "$target" || return 1
  done
  for target in "${_AGENT_RULES_PREVIOUS_TARGETS[@]+"${_AGENT_RULES_PREVIOUS_TARGETS[@]}"}"; do
    _agent_rules_prune_target "$target" || return 1
  done
  _agent_rules_consume_legacy_state || return 1
  _agent_rules_remove_state
}

agent_rules_uninstall() {
  local status
  _agent_rules_validate_runtime_paths || return 1
  _agent_rules_acquire_lock || return 1
  _agent_rules_uninstall_locked
  status=$?
  _agent_rules_release_lock || status=1
  return "$status"
}
