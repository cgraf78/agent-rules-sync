# Design and ownership

## Boundary

agent-rules-sync owns behavior that is reusable across policy repositories and
configuration managers:

- strict versioned-manifest parsing and source-metadata validation;
- authoritative rule and playbook order, playbook route rendering, and the
  exactly-once index contract;
- Claude, Codex, Gemini, OpenCode, installed-agent, and absolute custom-file
  target expansion;
- managed-block publication, permissions, idempotence, durable target state,
  stale cleanup, and uninstall; and
- conservative takeover of the exact historical dot publisher artifacts.

Consumers own all policy:

- the rule and playbook prose;
- which repositories, overlay links, or files are trusted;
- the ordered rule and playbook manifest records;
- target selection and activation timing; and
- the provider dependency declaration.

This is why the provider accepts a resolved manifest instead of scanning a
conventional source directory. Discovery would move trust policy into a public
utility and either weaken a configuration manager's overlay checks or couple
the sync utility to one repository layout.

## Route and source are separate

A playbook route is the stable path agents see in their generated routing
index. Its source is the absolute file already authorized by the orchestrator.
Keeping them separate supports an overlay-owned source without exposing that
overlay's path as the runtime route, and it avoids asking agent-rules-sync to infer
whether a symlink, checkout, or local filesystem source is trustworthy.

The manifest order is final. The provider does not sort fragments or routes,
because ordering is policy and therefore belongs to the caller.

## Publication model

One managed block is appended after normalized unmanaged target content. The
provider strips both its current marker and the exact retired dot marker family
in memory, then atomically replaces the target. A malformed or unterminated
marker fails closed so text after it cannot be accidentally discarded.
Rule fragments containing those exact ownership delimiter lines are rejected
up front; otherwise an embedded delimiter could make the next reconciliation
interpret generated prose as a nested managed block.

Manifest parsing, source reads, identifier validation, playbook expansion, and
previous-state validation all happen before the first target mutation. Target
files are individually atomic; publishing several independent agent files is
not a filesystem-wide transaction. If a later mutation fails, durable state is
not advanced, so the next reconciliation retries the full target set and stale
cleanup.

A portable private `mkdir` lock serializes publication, pruning, and inventory
updates. Active ownership fails a second invocation before mutation, while a
dead PID can be reclaimed behind a separate atomic reclaim gate. This avoids a
dependency on `flock`, which is not present on every supported macOS host.

Destination mode is `0600`, including mode-only repair when content is already
current. A newly created immediate parent is `0700`, while an existing parent
retains its owner-selected mode. Validated same-directory temporary files keep
rename atomic on the destination filesystem; cleanup removes files only and
never recursively deletes an untrusted `mktemp` result.

## Durable state rather than cache

The target inventory belongs under `XDG_STATE_HOME`, not cache, because it is
needed to safely remove a custom target after the policy that named it has been
removed. Losing cache may cost work; losing this inventory could strand a
generated rule block.

The state file stores only an allowlisted version record and absolute target
records. Target parents are resolved before publication and persistence, which
keeps the old destination addressable if a configured symlink is later
retargeted. Cleanup strips a positively identified managed block and preserves
everything else. Known built-in paths can be checked safely during uninstall
even without state; an unrecorded custom path cannot and is left alone.

## Migration

The retired implementation published `dot-managed:agent-rules` blocks and
recorded target paths in one versioned v3 dot state file. It is accepted only
when its exact historical version is recognized. Successful publication,
pruning, and new-state storage precede removal of that old inventory.

An even older publisher linked individual Markdown fragments and recorded
directories in a v1 cache. That cache is no longer migration authority. In
particular, `$HOME/.config/agent-rules` is an ordinary caller-owned source
location; sync never scans or deletes links merely because they relate to that
tree.

## Packaging

The repository ships one thin Bash launcher and provider-private sourced
modules. `install.sh` symlinks the launcher rather than copying it so a checkout
update cannot leave command and implementation versions out of sync. Bash 4.0
is the minimum supported runtime because manifest and target duplicate checks
use associative arrays.
