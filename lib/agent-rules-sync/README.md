# Provider library

These modules are private implementation details behind `bin/agent-rules-sync`:

- `paths.sh` owns HOME, XDG, state, and built-in agent paths;
- `temp.sh` owns same-directory scratch files and signal cleanup;
- `manifest.sh` parses and validates the non-evaluated TSV contract;
- `render.sh` expands the ordered playbook index and rule body;
- `managed.sh` publishes and removes conservative marked blocks;
- `targets.sh` expands explicit and installed public agents;
- `lock.sh` enforces one reconciliation writer without requiring `flock`;
- `migration.sh` owns durable target state and exact legacy takeover; and
- `api.sh` sequences sync and uninstall only after validation succeeds.

The files are sourceable Bash libraries, not independent commands. They return
errors to their caller and do not enable shell options or export variables.
Only the public launcher installs process-level traps; the lock module exposes
cleanup for those launcher-owned traps.
