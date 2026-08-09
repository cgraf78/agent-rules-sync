# Synthetic manifest example

The files in this directory demonstrate the metadata shape without containing
any personal policy. Copy the rule and playbook files to caller-owned policy
directories, then create a manifest with absolute paths:

```bash
policy_root=/absolute/path/to/policy
manifest=/absolute/path/to/manifest.tsv

printf '%s\t%s\n' \
  version agent-rules-sync-manifest-v1 \
  rule-root "$policy_root/rules.d" \
  playbook-root "$policy_root/playbooks.d" \
  rule "$policy_root/rules.d/000-example.md" \
  >"$manifest"
printf 'playbook\t%s\t%s\n' \
  example/workflow.md "$policy_root/playbooks.d/example/workflow.md" \
  >>"$manifest"
printf 'target\t%s\n' claude >>"$manifest"

agent-rules-sync --manifest "$manifest"
```

The shell snippet is illustrative; a configuration manager should write the
manifest atomically after performing its own repository and overlay trust
checks.
