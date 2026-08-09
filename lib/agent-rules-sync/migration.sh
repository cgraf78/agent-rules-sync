# shellcheck shell=bash
# Durable target inventory and conservative takeover of retired dot outputs.

_AGENT_RULES_PREVIOUS_TARGETS=()
declare -A _AGENT_RULES_PREVIOUS_TARGET_SEEN=()

_agent_rules_previous_reset() {
  _AGENT_RULES_PREVIOUS_TARGETS=()
  _AGENT_RULES_PREVIOUS_TARGET_SEEN=()
}

_agent_rules_add_previous_target() {
  local target="$1"
  _agent_rules_require_absolute "stored target path" "$target" || return 1
  [[ -n "${_AGENT_RULES_PREVIOUS_TARGET_SEEN[$target]+x}" ]] && return 0
  _AGENT_RULES_PREVIOUS_TARGET_SEEN["$target"]=1
  _AGENT_RULES_PREVIOUS_TARGETS+=("$target")
}

_agent_rules_load_state_file() {
  local file="$1" line key value version_seen=0
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    _AGENT_RULES_LINE=0
    _agent_rules_split_two "$line" || return 1
    key=${line%%$'\t'*}
    value="$REPLY_FIRST"
    case "$key" in
      version)
        [[ "$value" == agent-rules-sync-targets-v1 && "$version_seen" -eq 0 ]] || {
          _agent_rules_error "invalid target inventory version: $value"
          return 1
        }
        version_seen=1
        ;;
      target) _agent_rules_add_previous_target "$value" || return 1 ;;
      *)
        _agent_rules_error "invalid target inventory record: $key"
        return 1
        ;;
    esac
  done <"$file"
  ((version_seen == 1)) || {
    _agent_rules_error "target inventory has no version: $file"
    return 1
  }
}

_agent_rules_load_legacy_cache() {
  local file="$1"
  local line key value _rest version_seen=0
  [[ -f "$file" ]] || return 0
  while IFS=$'\t' read -r key value _rest || [[ -n "$key$value$_rest" ]]; do
    case "$key" in
      version)
        if ((version_seen)) || [[ "$value" != dotfiles-agent-rules-cache-v3 ]]; then
          _agent_rules_error \
            "unsupported legacy target inventory version: $value ($file)"
          return 1
        fi
        version_seen=1
        ;;
      target)
        [[ -n "$value" ]] || continue
        _agent_rules_add_previous_target "$value" || return 1
        ;;
    esac
  done <"$file"
  if ((version_seen == 0)); then
    _agent_rules_error \
      "unsupported legacy target inventory version: missing ($file)"
    return 1
  fi
}

_agent_rules_load_previous() {
  local state legacy_v3
  _agent_rules_previous_reset
  state=$(_agent_rules_state_file) || return 1
  legacy_v3=$(_agent_rules_legacy_cache_v3) || return 1
  _agent_rules_load_state_file "$state" || return 1
  _agent_rules_load_legacy_cache "$legacy_v3" || return 1
}

_agent_rules_prune_stale() {
  local target status
  for target in "${_AGENT_RULES_PREVIOUS_TARGETS[@]+"${_AGENT_RULES_PREVIOUS_TARGETS[@]}"}"; do
    _agent_rules_target_path_selected "$target"
    status=$?
    case "$status" in
      0) continue ;;
      1) ;;
      *)
        _agent_rules_error "cannot safely reconcile stored target: $target"
        return 1
        ;;
    esac
    _agent_rules_prune_target "$target" || return 1
  done
}

_agent_rules_write_state() {
  local state tmp target
  state=$(_agent_rules_state_file) || return 1
  _agent_rules_sibling_tmp_for "$state" || return 1
  tmp="$REPLY"
  {
    printf 'version\tagent-rules-sync-targets-v1\n'
    for target in "${_AGENT_RULES_TARGET_PATHS[@]+"${_AGENT_RULES_TARGET_PATHS[@]}"}"; do
      printf 'target\t%s\n' "$target"
    done
  } >"$tmp" || return 1
  chmod 600 "$tmp" || return 1
  _agent_rules_publish_tmp "$tmp" "$state" || return 1
  chmod 700 "${state%/*}" || return 1
}

_agent_rules_consume_legacy_state() {
  local legacy_v3
  legacy_v3=$(_agent_rules_legacy_cache_v3) || return 1
  rm -f -- "$legacy_v3"
}

_agent_rules_remove_state() {
  local state state_dir
  state=$(_agent_rules_state_file) || return 1
  state_dir=${state%/*}
  rm -f -- "$state" || return 1
  rmdir "$state_dir" 2>/dev/null || true
}
