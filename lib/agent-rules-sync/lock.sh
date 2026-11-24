# shellcheck shell=bash
# Portable single-writer ownership for target and state reconciliation.

_AGENT_RULES_LOCK_PREFIX=agent-rules-sync-owner
_AGENT_RULES_LOCK_PATH=''
_AGENT_RULES_RECLAIM_PATH=''

_agent_rules_lock_path() {
  local state
  state=$(_agent_rules_state_file) || return 1
  printf '%s/lock\n' "${state%/*}"
}

_agent_rules_lock_record() {
  REPLY="$_AGENT_RULES_LOCK_PREFIX/$$/${1##*/}"
}

_agent_rules_publish_lock() {
  local lock="$1"
  _agent_rules_lock_record "$lock"
  # Passing the parent with a trailing slash makes ln append the source
  # basename. It cannot descend into a legacy lock directory or create a
  # link at the parent path if the parent disappears. The PID and ownership
  # become visible together in the intentionally dangling link.
  ln -s "$REPLY" "${lock%/*}/" 2>/dev/null
}

_agent_rules_read_lock_link() {
  local record
  # Read without an output delimiter, then keep Bash from stripping a
  # trailing newline that belongs to the link itself.
  record=$(readlink -n "$1" 2>/dev/null && printf '.') || return 1
  REPLY=${record%.}
}

_agent_rules_lock_owner() {
  local lock="$1" prefix="$_AGENT_RULES_LOCK_PREFIX/" suffix="/${1##*/}"
  if [[ -L "$lock" ]]; then
    _agent_rules_read_lock_link "$lock" || return 1
    [[ "$REPLY" == "$prefix"*"$suffix" ]] || return 1
    REPLY=${REPLY#"$prefix"}
    REPLY=${REPLY%"$suffix"}
  elif [[ -d "$lock" && -f "$lock/pid" && ! -L "$lock/pid" ]]; then
    REPLY=$(<"$lock/pid") || return 1
  else
    return 1
  fi
  [[ "$REPLY" =~ ^[1-9][0-9]*$ ]]
}

_agent_rules_owns_lock_link() {
  local lock="$1" record
  [[ -L "$lock" ]] || return 1
  _agent_rules_read_lock_link "$lock" || return 1
  record=$REPLY
  _agent_rules_lock_record "$lock"
  [[ "$record" == "$REPLY" ]]
}

_agent_rules_take_reclaim() {
  # Register the candidate before ln so a signal after creation can clean it.
  _AGENT_RULES_RECLAIM_PATH="$1"
  if ! _agent_rules_publish_lock "$1"; then
    _AGENT_RULES_RECLAIM_PATH=''
    return 1
  fi
}

_agent_rules_release_reclaim() {
  if [[ -n "$_AGENT_RULES_RECLAIM_PATH" ]] &&
    _agent_rules_owns_lock_link "$_AGENT_RULES_RECLAIM_PATH"; then
    rm -f -- "$_AGENT_RULES_RECLAIM_PATH" || return 1
  fi
  _AGENT_RULES_RECLAIM_PATH=''
}

_agent_rules_remove_stale_lock() {
  local lock="$1" entry
  if [[ -L "$lock" ]]; then
    rm -- "$lock"
    return
  fi
  # A legacy lock should contain only its owner record. Preserve it when
  # unexpected contents prevent rmdir from reclaiming the directory.
  for entry in "$lock"/* "$lock"/.[!.]* "$lock"/..?*; do
    [[ "$entry" == "$lock/pid" || (! -e "$entry" && ! -L "$entry") ]] && continue
    _agent_rules_error "refusing to reclaim nonempty agent-rules-sync lock: $lock"
    return 1
  done
  # Finish both removals before the launcher's signal trap can release the
  # guard. An empty legacy directory would be indistinguishable from a live
  # older invocation that has yet to write its PID.
  (
    trap '' HUP INT TERM
    rm -- "$lock/pid" && rmdir "$lock"
  )
}

_agent_rules_acquire_primary() {
  local lock="$1" owner
  if _agent_rules_publish_lock "$lock"; then
    return 0
  fi
  if [[ ! -e "$lock" && ! -L "$lock" ]]; then
    _agent_rules_error "could not create agent-rules-sync lock: $lock"
    return 1
  fi
  if ! _agent_rules_lock_owner "$lock"; then
    _agent_rules_error "invalid or incomplete agent-rules-sync lock: $lock; verify no invocation is running before removing it"
    return 1
  fi
  owner=$REPLY
  if kill -0 "$owner" 2>/dev/null; then
    _agent_rules_error "another agent-rules-sync invocation is active"
    return 1
  fi
  # A legacy writer can finish and another legacy writer can acquire its
  # directory without the reclaim guard. Check again after probing the PID.
  if ! _agent_rules_lock_owner "$lock" || [[ "$REPLY" != "$owner" ]]; then
    _agent_rules_error "agent-rules-sync lock changed during acquisition: $lock; retry"
    return 1
  fi
  _agent_rules_remove_stale_lock "$lock" || return 1
  if ! _agent_rules_publish_lock "$lock"; then
    _agent_rules_error "could not acquire agent-rules-sync lock: $lock; retry"
    return 1
  fi
}

_agent_rules_acquire_lock() {
  local lock parent reclaim status=0
  lock=$(_agent_rules_lock_path) || return 1
  if _agent_rules_lock_owner "$lock" && kill -0 "$REPLY" 2>/dev/null; then
    _agent_rules_error "another agent-rules-sync invocation is active"
    return 1
  fi

  parent=${lock%/*}
  reclaim="$lock.reclaim"
  mkdir -p "$parent" || return 1
  chmod 700 "$parent" || return 1
  if ! _agent_rules_take_reclaim "$reclaim"; then
    _agent_rules_error "could not acquire agent-rules-sync lock guard: $reclaim; retry, or verify no invocation is running before removing a leftover guard"
    return 1
  fi
  _AGENT_RULES_LOCK_PATH="$lock"
  _agent_rules_acquire_primary "$lock" || status=$?
  _agent_rules_release_reclaim || status=1
  return "$status"
}

_agent_rules_release_lock() {
  local lock="$_AGENT_RULES_LOCK_PATH" reclaim status=0
  if [[ -z "$lock" ]] || ! _agent_rules_owns_lock_link "$lock"; then
    _AGENT_RULES_LOCK_PATH=''
    _agent_rules_release_reclaim
    return
  fi
  reclaim="$lock.reclaim"
  # Protect unlink as well as publication: if the shell is killed while its
  # rm child is still running, no other writer can replace this lock first.
  # If a contender holds the guard, leave a fully identified lock to reclaim.
  if ! _agent_rules_owns_lock_link "$reclaim" && ! _agent_rules_take_reclaim "$reclaim"; then
    return 0
  fi
  if rm -- "$lock"; then
    _AGENT_RULES_LOCK_PATH=''
  else
    status=1
  fi
  _agent_rules_release_reclaim || status=1
  rmdir "${lock%/*}" 2>/dev/null || true
  return "$status"
}
