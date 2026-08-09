# shellcheck shell=bash
# Portable single-writer ownership for target and state reconciliation.

_AGENT_RULES_LOCK_DIR=''
_AGENT_RULES_LOCK_HELD=0
_AGENT_RULES_RECLAIM_DIR=''
_AGENT_RULES_RECLAIM_HELD=0

_agent_rules_lock_dir() {
  local state
  state=$(_agent_rules_state_file) || return 1
  printf '%s/lock\n' "${state%/*}"
}

_agent_rules_lock_owner_is_live() {
  local lock="$1" owner
  [[ -f "$lock/pid" && ! -L "$lock/pid" ]] || return 1
  owner=$(<"$lock/pid")
  [[ "$owner" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$owner" 2>/dev/null
}

_agent_rules_create_lock() {
  local lock="$1"
  mkdir "$lock" 2>/dev/null || return 1
  if ! chmod 700 "$lock" || ! printf '%s\n' "$$" >"$lock/pid" ||
    ! chmod 600 "$lock/pid"; then
    rm -f "$lock/pid" 2>/dev/null || true
    rmdir "$lock" 2>/dev/null || true
    return 1
  fi
  _AGENT_RULES_LOCK_DIR="$lock"
  _AGENT_RULES_LOCK_HELD=1
}

_agent_rules_release_reclaim() {
  if [[ "$_AGENT_RULES_RECLAIM_HELD" -eq 1 ]]; then
    rmdir "$_AGENT_RULES_RECLAIM_DIR" 2>/dev/null || true
  fi
  _AGENT_RULES_RECLAIM_DIR=''
  _AGENT_RULES_RECLAIM_HELD=0
}

_agent_rules_acquire_lock() {
  local lock parent reclaim
  lock=$(_agent_rules_lock_dir) || return 1
  parent=${lock%/*}
  mkdir -p "$parent" || return 1
  chmod 700 "$parent" || return 1
  if _agent_rules_create_lock "$lock"; then
    return 0
  fi
  if [[ -L "$lock" || ! -d "$lock" ]]; then
    _agent_rules_error "invalid agent-rules-sync lock path: $lock"
    return 1
  fi

  # Re-check ownership while holding a second atomic directory. Without this
  # gate, two processes that observe one stale PID could both remove and then
  # replace the primary lock.
  reclaim="$lock.reclaim"
  if ! mkdir "$reclaim" 2>/dev/null; then
    _agent_rules_error "another agent-rules-sync invocation is acquiring the lock"
    return 1
  fi
  _AGENT_RULES_RECLAIM_DIR="$reclaim"
  _AGENT_RULES_RECLAIM_HELD=1
  chmod 700 "$reclaim" || {
    _agent_rules_release_reclaim
    return 1
  }

  # The original owner may have exited between the failed mkdir and the
  # reclaim gate. If it already removed the primary directory, create ours
  # while the gate still excludes other compliant contenders.
  if [[ ! -e "$lock" && ! -L "$lock" ]]; then
    if ! _agent_rules_create_lock "$lock"; then
      _agent_rules_release_reclaim
      _agent_rules_error "could not acquire agent-rules-sync lock: $lock"
      return 1
    fi
    _agent_rules_release_reclaim
    return 0
  fi
  if [[ -L "$lock" || ! -d "$lock" ]]; then
    _agent_rules_release_reclaim
    _agent_rules_error "invalid agent-rules-sync lock path: $lock"
    return 1
  fi
  if _agent_rules_lock_owner_is_live "$lock"; then
    _agent_rules_release_reclaim
    _agent_rules_error "another agent-rules-sync invocation is active"
    return 1
  fi
  if [[ -L "$lock/pid" ]]; then
    _agent_rules_release_reclaim
    _agent_rules_error "invalid agent-rules-sync lock owner file: $lock/pid"
    return 1
  fi
  rm -f "$lock/pid" || {
    _agent_rules_release_reclaim
    return 1
  }
  if ! rmdir "$lock" 2>/dev/null; then
    _agent_rules_release_reclaim
    _agent_rules_error "refusing to reclaim nonempty agent-rules-sync lock: $lock"
    return 1
  fi
  if ! _agent_rules_create_lock "$lock"; then
    _agent_rules_release_reclaim
    _agent_rules_error "could not acquire agent-rules-sync lock: $lock"
    return 1
  fi
  _agent_rules_release_reclaim
}

_agent_rules_release_lock() {
  local owner='' parent
  _agent_rules_release_reclaim
  if [[ "$_AGENT_RULES_LOCK_HELD" -eq 0 ]]; then
    return 0
  fi
  if [[ -f "$_AGENT_RULES_LOCK_DIR/pid" && ! -L "$_AGENT_RULES_LOCK_DIR/pid" ]]; then
    owner=$(<"$_AGENT_RULES_LOCK_DIR/pid")
  fi
  if [[ "$owner" == "$$" ]]; then
    rm -f "$_AGENT_RULES_LOCK_DIR/pid" || return 1
    rmdir "$_AGENT_RULES_LOCK_DIR" 2>/dev/null || return 1
    parent=${_AGENT_RULES_LOCK_DIR%/*}
    rmdir "$parent" 2>/dev/null || true
  fi
  _AGENT_RULES_LOCK_DIR=''
  _AGENT_RULES_LOCK_HELD=0
}
