# Public command

`agent-rules` is the only supported executable. It resolves symlink installs
back to this checkout, verifies Bash 4 before sourcing private modules, parses
the small public command surface, installs invocation-scoped scratch cleanup,
and delegates to `lib/agent-rules/api.sh`.

Keep policy selection, rendering, and filesystem ownership behavior out of the
launcher. That logic belongs in the provider modules where the direct behavior
suites can exercise it without duplicating CLI parsing.
