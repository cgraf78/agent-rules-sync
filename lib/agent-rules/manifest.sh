# shellcheck shell=bash
# Parse the orchestrator-selected, versioned TSV manifest without evaluation.

_AGENT_RULES_MANIFEST_VERSION=agent-rules-manifest-v1
_AGENT_RULES_MANIFEST_FILE=''
_AGENT_RULES_RULE_ROOT=''
_AGENT_RULES_PLAYBOOK_ROOT=''
_AGENT_RULES_RULE_FILES=()
_AGENT_RULES_RULE_CONTENTS=()
_AGENT_RULES_PLAYBOOK_ROUTES=()
_AGENT_RULES_PLAYBOOK_FILES=()
_AGENT_RULES_PLAYBOOK_TRIGGERS=()
_AGENT_RULES_TARGET_IDS=()
_AGENT_RULES_CUSTOM_TARGETS=()
declare -A _AGENT_RULES_RULE_SEEN=()
declare -A _AGENT_RULES_PLAYBOOK_ROUTE_SEEN=()
declare -A _AGENT_RULES_PLAYBOOK_SOURCE_SEEN=()
declare -A _AGENT_RULES_TARGET_ID_SEEN=()
declare -A _AGENT_RULES_CUSTOM_TARGET_SEEN=()
declare -A _AGENT_RULES_ID_SOURCE=()

_agent_rules_manifest_reset() {
  _AGENT_RULES_MANIFEST_FILE=''
  _AGENT_RULES_RULE_ROOT=''
  _AGENT_RULES_PLAYBOOK_ROOT=''
  _AGENT_RULES_RULE_FILES=()
  _AGENT_RULES_RULE_CONTENTS=()
  _AGENT_RULES_PLAYBOOK_ROUTES=()
  _AGENT_RULES_PLAYBOOK_FILES=()
  _AGENT_RULES_PLAYBOOK_TRIGGERS=()
  _AGENT_RULES_TARGET_IDS=()
  _AGENT_RULES_CUSTOM_TARGETS=()
  _AGENT_RULES_RULE_SEEN=()
  _AGENT_RULES_PLAYBOOK_ROUTE_SEEN=()
  _AGENT_RULES_PLAYBOOK_SOURCE_SEEN=()
  _AGENT_RULES_TARGET_ID_SEEN=()
  _AGENT_RULES_CUSTOM_TARGET_SEEN=()
  _AGENT_RULES_ID_SOURCE=()
}

_agent_rules_manifest_fields() {
  local line="$1" expected="$2" rest count=1
  rest="$line"
  while [[ "$rest" == *$'\t'* ]]; do
    rest=${rest#*$'\t'}
    count=$((count + 1))
  done
  if [[ "$count" -ne "$expected" ]]; then
    _agent_rules_error \
      "manifest line $_AGENT_RULES_LINE has $count fields; expected $expected"
    return 1
  fi
}

_agent_rules_split_two() {
  local line="$1"
  _agent_rules_manifest_fields "$line" 2 || return 1
  REPLY_FIRST=${line#*$'\t'}
  REPLY_SECOND=''
}

_agent_rules_split_three() {
  local line="$1" rest
  _agent_rules_manifest_fields "$line" 3 || return 1
  rest=${line#*$'\t'}
  REPLY_FIRST=${rest%%$'\t'*}
  REPLY_SECOND=${rest#*$'\t'}
}

_agent_rules_readable_source() {
  local kind="$1" source="$2"
  _agent_rules_require_absolute "$kind source path" "$source" || return 1
  if [[ ! -f "$source" || ! -r "$source" ]]; then
    _agent_rules_error "$kind source is not a readable file: $source"
    return 1
  fi
}

_agent_rules_register_file_ids() {
  local file="$1" line id count=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '<!-- agent-rule-id: '*' -->')
        id=${line#'<!-- agent-rule-id: '}
        id=${id%' -->'}
        if [[ -z "$id" || "$id" == *[!A-Za-z0-9._-]* ]]; then
          _agent_rules_error \
            "$file has an invalid agent-rule-id; use letters, digits, dot, underscore, or dash"
          return 1
        fi
        count=$((count + 1))
        if [[ -n "${_AGENT_RULES_ID_SOURCE[$id]+x}" ]]; then
          _agent_rules_error \
            "duplicate agent-rule-id '$id': ${_AGENT_RULES_ID_SOURCE[$id]} and $file"
          return 1
        fi
        _AGENT_RULES_ID_SOURCE["$id"]="$file"
        ;;
    esac
  done <"$file"
  if [[ "$count" -lt 1 ]]; then
    _agent_rules_error \
      "$file must contain at least one agent-rule-id"
    return 1
  fi
}

_agent_rules_playbook_trigger() {
  local file="$1" line trigger='' count=0 title_seen=0 metadata_seen=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '') continue ;;
      '# '*)
        if ((title_seen || metadata_seen)); then
          break
        fi
        title_seen=1
        ;;
      '<!-- agent-rule-id: '*' -->') metadata_seen=1 ;;
      '<!-- agent-rule-trigger: '*' -->')
        metadata_seen=1
        trigger=${line#'<!-- agent-rule-trigger: '}
        trigger=${trigger%' -->'}
        count=$((count + 1))
        ;;
      *) break ;;
    esac
  done <"$file"
  if [[ "$count" -ne 1 || -z "$trigger" ]]; then
    _agent_rules_error \
      "$file must contain exactly one agent-rule-trigger in its leading metadata"
    return 1
  fi
  REPLY="$trigger"
}

_agent_rules_validate_playbook_route() {
  local route="$1" segment rest
  if [[ -z "$route" || "$route" == /* || "$route" == *'`'* ]] ||
    _agent_rules_value_has_control "$route"; then
    _agent_rules_error "unsafe playbook route: $route"
    return 1
  fi
  rest="$route"
  while :; do
    segment=${rest%%/*}
    case "$segment" in
      '' | . | ..)
        _agent_rules_error "unsafe playbook route: $route"
        return 1
        ;;
    esac
    [[ "$rest" == */* ]] || break
    rest=${rest#*/}
  done
  case "$route" in
    *.md) ;;
    *)
      _agent_rules_error "unsafe playbook route (expected .md): $route"
      return 1
      ;;
  esac
}

_agent_rules_validate_rule_content() {
  local source="$1" content="$2" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '# agent-rules:aggregate begin' | '# agent-rules:aggregate end' | \
        '# dot-managed:agent-rules:'*' begin' | \
        '# dot-managed:agent-rules:'*' end')
        _agent_rules_error \
          "$source contains a reserved managed marker: $line"
        return 1
        ;;
    esac
  done <<<"$content"
}

_agent_rules_add_rule() {
  local source="$1" content
  _agent_rules_readable_source rule "$source" || return 1
  if [[ -n "${_AGENT_RULES_RULE_SEEN[$source]+x}" ]]; then
    _agent_rules_error "duplicate rule source: $source"
    return 1
  fi
  content=$(<"$source")
  _agent_rules_validate_rule_content "$source" "$content" || return 1
  _agent_rules_register_file_ids "$source" || return 1
  _AGENT_RULES_RULE_SEEN["$source"]=1
  _AGENT_RULES_RULE_FILES+=("$source")
  _AGENT_RULES_RULE_CONTENTS+=("$content")
}

_agent_rules_add_playbook() {
  local route="$1" source="$2" trigger
  _agent_rules_validate_playbook_route "$route" || return 1
  _agent_rules_readable_source playbook "$source" || return 1
  if [[ -n "${_AGENT_RULES_PLAYBOOK_ROUTE_SEEN[$route]+x}" ]]; then
    _agent_rules_error "duplicate playbook route: $route"
    return 1
  fi
  if [[ -n "${_AGENT_RULES_PLAYBOOK_SOURCE_SEEN[$source]+x}" ]]; then
    _agent_rules_error "duplicate playbook source: $source"
    return 1
  fi
  _agent_rules_register_file_ids "$source" || return 1
  _agent_rules_playbook_trigger "$source" || return 1
  trigger="$REPLY"
  _AGENT_RULES_PLAYBOOK_ROUTE_SEEN["$route"]=1
  _AGENT_RULES_PLAYBOOK_SOURCE_SEEN["$source"]=1
  _AGENT_RULES_PLAYBOOK_ROUTES+=("$route")
  _AGENT_RULES_PLAYBOOK_FILES+=("$source")
  _AGENT_RULES_PLAYBOOK_TRIGGERS+=("$trigger")
}

_agent_rules_add_target_id() {
  local target="$1"
  case "$target" in
    claude | codex | gemini | opencode | installed) ;;
    *)
      _agent_rules_error "unsupported target: $target"
      return 1
      ;;
  esac
  if [[ -n "${_AGENT_RULES_TARGET_ID_SEEN[$target]+x}" ]]; then
    _agent_rules_error "duplicate target: $target"
    return 1
  fi
  _AGENT_RULES_TARGET_ID_SEEN["$target"]=1
  _AGENT_RULES_TARGET_IDS+=("$target")
}

_agent_rules_add_custom_target() {
  local target="$1"
  _agent_rules_require_absolute "target-file path" "$target" || return 1
  if _agent_rules_value_has_control "$target"; then
    _agent_rules_error "target-file path contains a control character"
    return 1
  fi
  if [[ -n "${_AGENT_RULES_CUSTOM_TARGET_SEEN[$target]+x}" ]]; then
    _agent_rules_error "duplicate target-file: $target"
    return 1
  fi
  _AGENT_RULES_CUSTOM_TARGET_SEEN["$target"]=1
  _AGENT_RULES_CUSTOM_TARGETS+=("$target")
}

_agent_rules_count_playbook_markers() {
  local content line count=0
  for content in "${_AGENT_RULES_RULE_CONTENTS[@]+"${_AGENT_RULES_RULE_CONTENTS[@]}"}"; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      case "$line" in
        '<!-- agent-rules-playbook-index -->' | '<!-- dot-playbook-index -->')
          count=$((count + 1))
          ;;
      esac
    done <<<"$content"
  done
  REPLY="$count"
}

_agent_rules_validate_playbook_index() {
  local expected=0
  _agent_rules_count_playbook_markers
  ((${#_AGENT_RULES_PLAYBOOK_ROUTES[@]} > 0)) && expected=1
  if [[ "$REPLY" -ne "$expected" ]]; then
    if [[ "$expected" -eq 1 ]]; then
      _agent_rules_error \
        "manifest requires exactly one playbook index marker; found $REPLY"
    else
      _agent_rules_error \
        "manifest allows no playbook index marker without playbooks; found $REPLY"
    fi
    return 1
  fi
}

_agent_rules_parse_manifest() {
  local manifest="$1" line key first second record=0
  local version_seen=0 rule_root_seen=0 playbook_root_seen=0
  _agent_rules_manifest_reset
  _agent_rules_require_absolute "manifest path" "$manifest" || return 1
  if [[ ! -f "$manifest" || ! -r "$manifest" ]]; then
    _agent_rules_error "manifest is not a readable file: $manifest"
    return 1
  fi
  _AGENT_RULES_MANIFEST_FILE="$manifest"
  _AGENT_RULES_LINE=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    _AGENT_RULES_LINE=$((_AGENT_RULES_LINE + 1))
    [[ -n "$line" ]] || continue
    case "$line" in '# '*) continue ;; esac
    record=$((record + 1))
    key=${line%%$'\t'*}
    if [[ "$record" -eq 1 && "$key" != version ]]; then
      _agent_rules_error "manifest first record must be version"
      return 1
    fi
    case "$key" in
      version)
        _agent_rules_split_two "$line" || return 1
        first="$REPLY_FIRST"
        ((version_seen == 0)) || {
          _agent_rules_error "duplicate version record"
          return 1
        }
        [[ "$first" == "$_AGENT_RULES_MANIFEST_VERSION" ]] || {
          _agent_rules_error "unsupported version: $first"
          return 1
        }
        version_seen=1
        ;;
      rule-root)
        _agent_rules_split_two "$line" || return 1
        first="$REPLY_FIRST"
        ((rule_root_seen == 0)) || {
          _agent_rules_error "duplicate rule-root record"
          return 1
        }
        _agent_rules_require_absolute rule-root "$first" || return 1
        _AGENT_RULES_RULE_ROOT="$first"
        rule_root_seen=1
        ;;
      playbook-root)
        _agent_rules_split_two "$line" || return 1
        first="$REPLY_FIRST"
        ((playbook_root_seen == 0)) || {
          _agent_rules_error "duplicate playbook-root record"
          return 1
        }
        _agent_rules_require_absolute playbook-root "$first" || return 1
        _AGENT_RULES_PLAYBOOK_ROOT="$first"
        playbook_root_seen=1
        ;;
      rule)
        _agent_rules_split_two "$line" || return 1
        _agent_rules_add_rule "$REPLY_FIRST" || return 1
        ;;
      playbook)
        _agent_rules_split_three "$line" || return 1
        first="$REPLY_FIRST"
        second="$REPLY_SECOND"
        _agent_rules_add_playbook "$first" "$second" || return 1
        ;;
      target)
        _agent_rules_split_two "$line" || return 1
        _agent_rules_add_target_id "$REPLY_FIRST" || return 1
        ;;
      target-file)
        _agent_rules_split_two "$line" || return 1
        _agent_rules_add_custom_target "$REPLY_FIRST" || return 1
        ;;
      *)
        _agent_rules_error "unknown manifest record on line $_AGENT_RULES_LINE: $key"
        return 1
        ;;
    esac
  done <"$manifest"

  ((version_seen == 1)) || {
    _agent_rules_error "manifest has no version record"
    return 1
  }
  ((rule_root_seen == 1)) || {
    _agent_rules_error "manifest has no rule-root record"
    return 1
  }
  ((playbook_root_seen == 1)) || {
    _agent_rules_error "manifest has no playbook-root record"
    return 1
  }
  _agent_rules_validate_playbook_index
}
