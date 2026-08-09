#!/usr/bin/env bash
# Install a version-coupled symlink back to this checkout.

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

target="$BIN_DIR/agent-rules"
if [[ (-e "$target" || -L "$target") && ! -L "$target" ]]; then
  printf 'agent-rules: refusing to replace non-symlink path: %s\n' \
    "$target" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
ln -sfn "$ROOT/bin/agent-rules" "$target"
printf 'installed agent-rules to %s\n' "$target"
