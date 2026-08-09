# shellcheck shell=bash
# Stable XDG and agent target paths.

_agent_rules_error() {
  printf 'agent-rules-sync: %s\n' "$*" >&2
}

_agent_rules_value_has_control() {
  case "$1" in
    *$'\n'*) return 0 ;;
  esac
  LC_ALL=C printf '%s' "$1" | grep -q '[[:cntrl:]]'
}

_agent_rules_require_absolute() {
  local description="$1" path="$2"
  if _agent_rules_value_has_control "$path"; then
    _agent_rules_error "$description contains a control character"
    return 1
  fi
  case "$path" in
    /*) return 0 ;;
    *)
      _agent_rules_error "$description must be absolute: $path"
      return 1
      ;;
  esac
}

# Resolve the filesystem identity of a path whose final components may not
# exist yet. `-ef` can compare existing files, but publication commonly creates
# a new target and a new state file in the same run. Walking to the nearest
# existing directory lets `pwd -P` resolve any parent symlink; the remaining
# lexical components are then normalized without creating anything.
#
# This is deliberately narrower than a general-purpose realpath replacement:
# callers have already required an absolute path, and only collision checks use
# the result. Keeping it here avoids adding a GNU-only `realpath -m` dependency
# on macOS and Termux.
_agent_rules_canonical_candidate() {
  local candidate="$1" existing segment tail='' resolved rest part path=''
  local -a parts=()

  _agent_rules_require_absolute "path" "$candidate" || return 1
  existing="$candidate"
  while [[ ! -d "$existing" ]]; do
    [[ "$existing" != / ]] || break
    segment=${existing##*/}
    existing=${existing%/*}
    [[ -n "$existing" ]] || existing=/
    [[ -n "$segment" ]] && tail="/$segment$tail"
  done
  resolved=$(cd -P -- "$existing" 2>/dev/null && pwd -P) || return 1
  rest=${resolved#/}${tail}

  while [[ -n "$rest" ]]; do
    if [[ "$rest" == */* ]]; then
      part=${rest%%/*}
      rest=${rest#*/}
    else
      part="$rest"
      rest=''
    fi
    case "$part" in
      '' | .) ;;
      ..)
        if ((${#parts[@]} > 0)); then
          unset "parts[${#parts[@]}-1]"
        fi
        ;;
      *) parts+=("$part") ;;
    esac
  done

  if ((${#parts[@]} == 0)); then
    REPLY=/
    return 0
  fi
  for part in "${parts[@]}"; do
    path+="/$part"
  done
  REPLY="$path"
}

_agent_rules_home() {
  local home=${HOME:-}
  _agent_rules_require_absolute HOME "$home" || return 1
  printf '%s\n' "$home"
}

_agent_rules_xdg_home() {
  local variable="$1" fallback="$2" home value
  value=${!variable:-}
  case "$value" in
    /*)
      _agent_rules_require_absolute "$variable" "$value" || return 1
      printf '%s\n' "$value"
      ;;
    *)
      home=$(_agent_rules_home) || return 1
      printf '%s/%s\n' "$home" "$fallback"
      ;;
  esac
}

_agent_rules_config_home() {
  _agent_rules_xdg_home XDG_CONFIG_HOME .config
}

_agent_rules_state_home() {
  _agent_rules_xdg_home XDG_STATE_HOME .local/state
}

agent_rules_default_manifest() {
  local root
  root=$(_agent_rules_config_home) || return 1
  printf '%s/agent-rules-sync/manifest.tsv\n' "$root"
}

_agent_rules_state_file() {
  local root
  root=$(_agent_rules_state_home) || return 1
  printf '%s/agent-rules-sync/targets-v1\n' "$root"
}

_agent_rules_legacy_cache_v3() {
  local root
  root=$(_agent_rules_state_home) || return 1
  printf '%s/dot/agent-rules-publish-cache-v3\n' "$root"
}

_agent_rules_builtin_target() {
  local agent="$1" home config
  case "$agent" in
    claude)
      home=$(_agent_rules_home) || return 1
      printf '%s/.claude/CLAUDE.md\n' "$home"
      ;;
    codex)
      home=$(_agent_rules_home) || return 1
      printf '%s/.codex/AGENTS.md\n' "$home"
      ;;
    gemini)
      home=$(_agent_rules_home) || return 1
      printf '%s/.gemini/GEMINI.md\n' "$home"
      ;;
    opencode)
      config=$(_agent_rules_config_home) || return 1
      printf '%s/opencode/AGENTS.md\n' "$config"
      ;;
    *)
      _agent_rules_error "unsupported target: $agent"
      return 1
      ;;
  esac
}

_agent_rules_validate_runtime_paths() {
  agent_rules_default_manifest >/dev/null || return 1
  _agent_rules_state_file >/dev/null || return 1
  _agent_rules_legacy_cache_v3 >/dev/null || return 1
  _agent_rules_builtin_target claude >/dev/null || return 1
  _agent_rules_builtin_target codex >/dev/null || return 1
  _agent_rules_builtin_target gemini >/dev/null || return 1
  _agent_rules_builtin_target opencode >/dev/null || return 1
}
