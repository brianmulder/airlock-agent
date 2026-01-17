#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STOW_DIR="$REPO_ROOT/stow"

command -v stow >/dev/null || {
  echo "stow not found. Install it first:"
  echo "  sudo apt-get update && sudo apt-get install -y stow"
  exit 1
}

mkdir -p "$HOME/bin" "$HOME/.airlock"

echo "--- Installing Airlock via stow ---"
stow -d "$STOW_DIR" -t "$HOME" airlock
echo "Done."
