# shellcheck shell=bash
# Expand built-in and installed-agent target policy into destination files.

_AGENT_RULES_TARGET_PATHS=()
declare -A _AGENT_RULES_TARGET_PATH_SEEN=()

_agent_rules_has_agent() {
  case "$1" in
    claude) command -v claude >/dev/null 2>&1 ;;
    codex) command -v codex >/dev/null 2>&1 ;;
    gemini) command -v gemini >/dev/null 2>&1 ;;
    opencode) command -v opencode >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

_agent_rules_add_target_path() {
  local target="$1" selected status
  _agent_rules_canonical_candidate "$target" || {
    _agent_rules_error "cannot resolve target destination: $target"
    return 1
  }
  target="$REPLY"
  [[ -n "${_AGENT_RULES_TARGET_PATH_SEEN[$target]+x}" ]] && return 0

  # Record the resolved parent identity and only one spelling for each
  # filesystem destination. This is more than cosmetic de-duplication:
  # persisting a symlinked spelling would lose the old destination if that
  # parent symlink moved, while persisting two aliases would let stale cleanup
  # remove a still-selected file through the second spelling.
  for selected in "${_AGENT_RULES_TARGET_PATHS[@]+"${_AGENT_RULES_TARGET_PATHS[@]}"}"; do
    _agent_rules_paths_alias "$target" "$selected"
    status=$?
    case "$status" in
      0) return 0 ;;
      1) ;;
      *)
        _agent_rules_error "cannot safely compare target destinations: $target"
        return 1
        ;;
    esac
  done
  _AGENT_RULES_TARGET_PATH_SEEN["$target"]=1
  _AGENT_RULES_TARGET_PATHS+=("$target")
}

_agent_rules_add_builtin_target() {
  local agent="$1" target
  target=$(_agent_rules_builtin_target "$agent") || return 1
  _agent_rules_add_target_path "$target"
}

_agent_rules_collect_targets() {
  local id agent target
  _AGENT_RULES_TARGET_PATHS=()
  _AGENT_RULES_TARGET_PATH_SEEN=()
  for id in "${_AGENT_RULES_TARGET_IDS[@]+"${_AGENT_RULES_TARGET_IDS[@]}"}"; do
    if [[ "$id" == installed ]]; then
      for agent in claude codex gemini opencode; do
        _agent_rules_has_agent "$agent" || continue
        _agent_rules_add_builtin_target "$agent" || return 1
      done
    else
      _agent_rules_add_builtin_target "$id" || return 1
    fi
  done
  for target in "${_AGENT_RULES_CUSTOM_TARGETS[@]+"${_AGENT_RULES_CUSTOM_TARGETS[@]}"}"; do
    _agent_rules_add_target_path "$target" || return 1
  done
}

_agent_rules_paths_alias() {
  local first="$1" second="$2" first_canonical second_canonical
  [[ "$first" == "$second" ]] && return 0
  if [[ -e "$first" && -e "$second" && "$first" -ef "$second" ]]; then
    return 0
  fi
  _agent_rules_canonical_candidate "$first" || return 2
  first_canonical="$REPLY"
  _agent_rules_canonical_candidate "$second" || return 2
  second_canonical="$REPLY"
  [[ "$first_canonical" == "$second_canonical" ]]
}

# Return success when a target from durable state names any currently selected
# destination, even if a symlink or normalized path gives it another spelling.
# Return 2 when identity cannot be established safely so cleanup can fail
# closed instead of pruning a potentially live target.
_agent_rules_target_path_selected() {
  local candidate="$1" selected status
  [[ -n "${_AGENT_RULES_TARGET_PATH_SEEN[$candidate]+x}" ]] && return 0
  for selected in "${_AGENT_RULES_TARGET_PATHS[@]+"${_AGENT_RULES_TARGET_PATHS[@]}"}"; do
    _agent_rules_paths_alias "$candidate" "$selected"
    status=$?
    case "$status" in
      0) return 0 ;;
      1) ;;
      *) return 2 ;;
    esac
  done
  return 1
}

_agent_rules_reject_target_collision() {
  local target="$1" reserved="$2" description="$3" status
  _agent_rules_paths_alias "$target" "$reserved"
  status=$?
  case "$status" in
    0)
      _agent_rules_error "target collides with $description: $target"
      return 1
      ;;
    1) return 0 ;;
    *)
      _agent_rules_error "cannot safely compare target with $description: $target"
      return 1
      ;;
  esac
}

# Lock ownership covers whole private directory trees rather than one file.
# Compare resolved identities here so a target cannot reach `lock/pid` or a
# reclaim-gate child through `..` components or a symlinked parent.
_agent_rules_reject_target_tree_collision() {
  local target="$1" reserved_root="$2" description="$3"
  local target_canonical root_canonical
  _agent_rules_canonical_candidate "$target" || {
    _agent_rules_error "cannot safely compare target with $description: $target"
    return 1
  }
  target_canonical="$REPLY"
  _agent_rules_canonical_candidate "$reserved_root" || {
    _agent_rules_error "cannot resolve $description: $reserved_root"
    return 1
  }
  root_canonical="$REPLY"
  case "$target_canonical" in
    "$root_canonical" | "$root_canonical"/*)
      _agent_rules_error "target collides with $description: $target"
      return 1
      ;;
  esac
}

_agent_rules_validate_target_collisions() {
  local target source state state_dir lock reclaim legacy_v3 legacy_v1
  state=$(_agent_rules_state_file) || return 1
  state_dir=${state%/*}
  lock="$state_dir/lock"
  reclaim="$lock.reclaim"
  legacy_v3=$(_agent_rules_legacy_cache_v3) || return 1
  legacy_v1=$(_agent_rules_legacy_cache_v1) || return 1
  for target in "${_AGENT_RULES_TARGET_PATHS[@]+"${_AGENT_RULES_TARGET_PATHS[@]}"}"; do
    _agent_rules_reject_target_tree_collision \
      "$target" "$lock" "provider lock state" || return 1
    _agent_rules_reject_target_tree_collision \
      "$target" "$reclaim" "provider reclaim state" || return 1
    _agent_rules_reject_target_collision \
      "$target" "$_AGENT_RULES_MANIFEST_FILE" manifest || return 1
    _agent_rules_reject_target_collision \
      "$target" "$state" "provider state" || return 1
    _agent_rules_reject_target_collision \
      "$target" "$legacy_v3" "legacy state" || return 1
    _agent_rules_reject_target_collision \
      "$target" "$legacy_v1" "legacy state" || return 1
    for source in "${_AGENT_RULES_RULE_FILES[@]+"${_AGENT_RULES_RULE_FILES[@]}"}"; do
      _agent_rules_reject_target_collision \
        "$target" "$source" "rule source" || return 1
    done
    for source in "${_AGENT_RULES_PLAYBOOK_FILES[@]+"${_AGENT_RULES_PLAYBOOK_FILES[@]}"}"; do
      _agent_rules_reject_target_collision \
        "$target" "$source" "playbook source" || return 1
    done
  done
}
