# shellcheck shell=bash
# Invocation-scoped temporary file ownership.

_AGENT_RULES_TEMP_PATHS=()
_AGENT_RULES_TEMP_TRAPS_ACTIVE=0

_agent_rules_track_temp() {
  _AGENT_RULES_TEMP_PATHS+=("$1")
}

_agent_rules_forget_temp() {
  local forgotten="$1" path
  local retained=()
  for path in "${_AGENT_RULES_TEMP_PATHS[@]+"${_AGENT_RULES_TEMP_PATHS[@]}"}"; do
    [[ "$path" == "$forgotten" ]] || retained+=("$path")
  done
  _AGENT_RULES_TEMP_PATHS=("${retained[@]+"${retained[@]}"}")
}

_agent_rules_cleanup_temps() {
  local path
  for path in "${_AGENT_RULES_TEMP_PATHS[@]+"${_AGENT_RULES_TEMP_PATHS[@]}"}"; do
    [[ -n "$path" ]] || continue
    rm -f -- "$path" 2>/dev/null || true
  done
  _AGENT_RULES_TEMP_PATHS=()
}

_agent_rules_cleanup_invocation() {
  _agent_rules_cleanup_temps
  if declare -F _agent_rules_release_lock >/dev/null 2>&1; then
    _agent_rules_release_lock || true
  fi
}

_agent_rules_forward_signal() {
  local signal="$1"
  trap - "$signal"
  _agent_rules_cleanup_invocation
  kill -s "$signal" "$$"
}

_agent_rules_install_temp_traps() {
  [[ "$_AGENT_RULES_TEMP_TRAPS_ACTIVE" -eq 0 ]] || return 0
  _AGENT_RULES_TEMP_TRAPS_ACTIVE=1
  trap '_agent_rules_cleanup_invocation' EXIT
  trap '_agent_rules_forward_signal HUP' HUP
  trap '_agent_rules_forward_signal INT' INT
  trap '_agent_rules_forward_signal TERM' TERM
}

_agent_rules_sibling_tmp_for() {
  local dst="$1" dir base tmp
  dir=${dst%/*}
  base=${dst##*/}
  [[ "$dir" != "$dst" ]] || dir=.
  mkdir -p -- "$dir" || return 1
  tmp=$(mktemp "$dir/${base}.tmp.XXXXXXXX" 2>/dev/null) || return 1
  case "$tmp" in
    "$dir/${base}.tmp."*) ;;
    *) return 1 ;;
  esac
  [[ -f "$tmp" && ! -L "$tmp" ]] || return 1
  _agent_rules_track_temp "$tmp"
  REPLY="$tmp"
}

_agent_rules_publish_tmp() {
  local tmp="$1" dst="$2"
  mv -- "$tmp" "$dst" || return 1
  _agent_rules_forget_temp "$tmp"
}
