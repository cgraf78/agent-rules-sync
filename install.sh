#!/usr/bin/env bash
# Install a version-coupled symlink back to this checkout.

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

source="$ROOT/bin/agent-rules-sync"
target="$BIN_DIR/agent-rules-sync"
if [[ ! -f "$source" || ! -x "$source" ]]; then
  printf 'agent-rules-sync: command source is not executable: %s\n' \
    "$source" >&2
  exit 1
fi
if [[ (-e "$target" || -L "$target") && ! -L "$target" ]]; then
  printf 'agent-rules-sync: refusing to replace non-symlink path: %s\n' \
    "$target" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
ln -sfn "$source" "$target"
printf 'installed agent-rules-sync to %s\n' "$target"
