# Test suites

`test/run` executes every behavior suite and, when `shellcheck` is on `PATH`,
the repository-owned ShellCheck inventory:

- `cli-test` covers public dispatch, manifest selection, XDG fallback, Bash
  version rejection, and signal cleanup;
- `provider-test` covers manifest validation, ordered rules and routes, all
  supported target selectors, grouped rule IDs, installed-agent discovery,
  and failure-before-mutation behavior;
- `managed-test` covers permissions, idempotent publication, durable state,
  target replacement, collision rejection, single-writer locking, dot-marker
  and versioned-state takeover, retired v1 link-cache non-authority,
  malformed-marker handling, and uninstall;
- `check-test` covers every `check` state, the exit-status contract that
  separates drift from invalid input and usage, owner-prose tolerance,
  prune-mode expectations, and proof that checking mutates nothing; and
- `install-test` covers symlink installation, overrides, idempotence, and
  collision safety.

Fixtures create complete synthetic rules, playbooks, manifests, homes, XDG
roots, and agent commands below a validated temporary root. They invoke the
real public executable and inspect real filesystem results. No suite reads or
modifies the user's installed rule files, and no fixture contains personal or
private policy prose.

Set `AGENT_RULES_SYNC_SKIP_SHELLCHECK=1` only when the surrounding CI job already
runs the same typed inventory through its shared ShellCheck profile.
