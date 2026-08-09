# agent-rules-sync

![Tests](https://github.com/cgraf78/agent-rules-sync/actions/workflows/test.yml/badge.svg?branch=main)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-blue.svg)](https://www.gnu.org/software/bash/)

`agent-rules-sync` synchronizes one shared rule document for Claude, Codex, Gemini,
OpenCode, and explicitly configured file targets. Ordered Markdown fragments
remain owned by the caller. A versioned manifest tells the provider exactly
which rule and playbook files are trusted, which order they use, and where the
result should be published.

```console
agent-rules-sync
agent-rules-sync --manifest /absolute/path/to/manifest.tsv
agent-rules-sync uninstall
```

The deliberately narrow boundary makes `agent-rules-sync` reusable with dotfiles,
another configuration manager, or a hand-authored manifest. It does not scan a
home directory, select policy, evaluate shell from configuration, or contain
the caller's actual rule and playbook prose.

## Installation

Clone the repository and install a PATH-visible symlink:

```bash
git clone https://github.com/cgraf78/agent-rules-sync.git
cd agent-rules-sync
./install.sh
```

`PREFIX` defaults to `$HOME/.local`; `BIN_DIR` can override its `bin` child.
The symlink resolves back to the matching checkout, keeping the launcher and
private shell library version-coupled. Dependency managers can instead expose
`bin/agent-rules-sync` directly. For example, a shdeps entry is:

```text
cgraf78/agent-rules-sync  github
```

## Manifest

The default manifest is:

```text
$XDG_CONFIG_HOME/agent-rules-sync/manifest.tsv
```

When `XDG_CONFIG_HOME` is unset or relative, it falls back to
`$HOME/.config`. `AGENT_RULES_SYNC_MANIFEST` selects another absolute manifest;
`--manifest` has the same purpose for one invocation and takes precedence.

The file is a strict tab-separated record stream. Its first nonempty record is
the version, rule and playbook roots occur once, and remaining records retain
their manifest order:

```text
version<TAB>agent-rules-sync-manifest-v1
rule-root<TAB>/absolute/policy/rules.d
playbook-root<TAB>/absolute/policy/playbooks.d
rule<TAB>/absolute/policy/rules.d/000-example.md
playbook<TAB>git/example.md<TAB>/absolute/authorized/example.md
target<TAB>claude
target<TAB>codex
target-file<TAB>/absolute/custom/AGENTS.md
```

`rule-root` and `playbook-root` describe the caller-owned policy roots. Rule
records point at ordered source files. A playbook record deliberately carries
both its relative route and its authorized absolute source: a configuration
manager can validate an overlay or symlink itself, then pass only that resolved
decision to this provider. The provider never needs to understand the caller's
repository, overlay, fleet, or trust model.

Every rule fragment has one or more globally unique identifiers, allowing a
caller to group related rules without losing independently addressable IDs:

```markdown
<!-- agent-rule-id: example-rule -->
```

Each playbook likewise has one or more globally unique identifiers, and has
exactly one trigger in its leading title/metadata block:

```markdown
# Example playbook

<!-- agent-rule-id: example-playbook -->
<!-- agent-rule-trigger: When the example workflow applies -->
```

When at least one playbook is selected, exactly one rule fragment contains:

```markdown
<!-- agent-rules-sync-playbook-index -->
```

The marker expands in place to ordered `trigger: route` entries. Playbook
bodies are not copied into the global rule document; agents load the routed
file only when its trigger applies. The retired
`<!-- dot-playbook-index -->` spelling is accepted solely to make migration
non-disruptive.

Blank lines and comments beginning with `# ` are allowed in the manifest.
Records reject missing or extra fields, duplicate sources, identifiers,
routes, and targets, unreadable sources, relative source or destination paths,
unsafe playbook routes, reserved output ownership delimiters, unknown records,
unsupported versions, and destinations that alias the manifest, a selected
source, or provider state. Validation and rendering finish before any
destination is modified.

See [`examples/README.md`](examples/README.md) for a complete synthetic setup.

## Targets

Explicit target IDs always publish their corresponding file:

| Target | Destination |
| --- | --- |
| `claude` | `$HOME/.claude/CLAUDE.md` |
| `codex` | `$HOME/.codex/AGENTS.md` |
| `gemini` | `$HOME/.gemini/GEMINI.md` |
| `opencode` | `$XDG_CONFIG_HOME/opencode/AGENTS.md` |

`target installed` expands only to those four public built-ins whose commands
are available on `PATH`. Explicit and installed targets can be combined;
duplicate destination files are written once. `target-file` supports an
absolute custom destination without teaching this public provider about a
private or future agent.

## Ownership and cleanup

Generated content is enclosed by:

```text
# agent-rules-sync:aggregate begin
...
# agent-rules-sync:aggregate end
```

Unmanaged text outside the block is preserved. Changed files are replaced
atomically through validated same-directory temporary files and made mode
`0600`; a newly created parent directory is mode `0700`. Repeated syncs with
unchanged content do not replace the file, but do repair a widened target mode
back to `0600`.

The active target inventory is durable state at:

```text
$XDG_STATE_HOME/agent-rules-sync/targets-v1
```

It lets a later sync prune managed blocks from deselected custom targets and
lets `uninstall` work after the manifest disappears. State falls back to
`$HOME/.local/state`. Inventory entries use each destination's resolved parent
identity, so moving a symlinked target parent does not strand the managed block
at its old destination. The provider removes a destination file only when no
unmanaged text remains.

A sync recognizes the exact historical `dot-managed:agent-rules` block family
and the retired dot target inventories below `$XDG_STATE_HOME/dot`. It can also
retire fragment symlinks recorded by the old publisher, but only when their
resolved source is below the exact historical `$HOME/.config/agent-rules`
tree. Unknown directories, links, files, and unmanaged target text remain
untouched.

`uninstall` removes provider-owned blocks from recorded targets and known
built-ins, then removes provider state. It does not delete manifests, source
fragments, playbooks, unmanaged target text, or unrecorded custom files.

Sync and uninstall use a private `mkdir` lock beside the target inventory. An
active owner makes a concurrent invocation fail before mutation; a dead PID is
reclaimed conservatively. This keeps publication, stale pruning, and inventory
replacement under one writer without requiring the non-portable `flock`
command.

## Failure behavior

Malformed manifests, source metadata, ownership delimiters, migration versions,
locks, or durable state return status 1. Invalid CLI usage returns status 2. A
validation or render failure leaves the last valid artifacts intact. A
filesystem failure is fatal and retains the last durable target inventory so
the next invocation can retry cleanup.

The CLI owns scratch-file signal traps and preserves conventional HUP, INT,
and TERM statuses. It requires Bash 4.0 or newer for associative arrays and
otherwise uses common Unix tools including `awk`, `cat`, `cmp`, `grep`,
`mktemp`, `readlink`, `sed`, and `stat` in tests.

## Development

Run the complete behavior, installer, and ShellCheck suite:

```bash
test/run
```

All fixtures contain synthetic public rules and playbooks inside validated
temporary homes. They never inspect or modify installed agent targets. See
[`test/README.md`](test/README.md) and [`docs/design.md`](docs/design.md) for
the testing and ownership rationale.

## License

MIT. See [`LICENSE`](LICENSE).
