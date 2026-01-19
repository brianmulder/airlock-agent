#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STOW_DIR="$REPO_ROOT/stow"
PKG_DIR="$STOW_DIR/airlock"

INSTALL_MODE="${AIRLOCK_INSTALL_MODE:-auto}"
case "$INSTALL_MODE" in
  auto)
    if command -v stow >/dev/null 2>&1; then
      INSTALL_MODE="stow"
    else
      INSTALL_MODE="symlink"
    fi
    ;;
  stow|symlink) ;;
  *)
    echo "ERROR: unknown AIRLOCK_INSTALL_MODE=$INSTALL_MODE (expected: auto|stow|symlink)" >&2
    exit 1
    ;;
esac

mkdir -p "$HOME/bin" "$HOME/.airlock"

if [[ "$INSTALL_MODE" == "stow" ]]; then
  command -v stow >/dev/null 2>&1 || {
    echo "ERROR: stow not found (AIRLOCK_INSTALL_MODE=stow)" >&2
    echo "Hint: sudo apt-get update && sudo apt-get install -y stow" >&2
    exit 1
  }

  echo "--- Installing Airlock via stow ---"
  stow -d "$STOW_DIR" -t "$HOME" airlock
  echo "Done."
  exit 0
fi

echo "--- Installing Airlock via symlinks (no stow) ---"

safe_symlink() {
  local src="$1"
  local dst="$2"

  [[ -e "$src" ]] || { echo "ERROR: missing install source: $src" >&2; exit 1; }

  if [[ -e "$dst" || -L "$dst" ]]; then
    if [[ -L "$dst" ]]; then
      # Replace existing symlink.
      rm -f "$dst"
    else
      echo "ERROR: destination exists and is not a symlink: $dst" >&2
      echo "Hint: remove it, or install via stow (AIRLOCK_INSTALL_MODE=stow)." >&2
      exit 1
    fi
  fi

  ln -s "$src" "$dst"
}

safe_symlink "$PKG_DIR/bin/yolo" "$HOME/bin/yolo"
safe_symlink "$PKG_DIR/bin/airlock" "$HOME/bin/airlock"
safe_symlink "$PKG_DIR/bin/airlock-build" "$HOME/bin/airlock-build"
safe_symlink "$PKG_DIR/bin/airlock-doctor" "$HOME/bin/airlock-doctor"
safe_symlink "$PKG_DIR/bin/airlock-wsl-prereqs" "$HOME/bin/airlock-wsl-prereqs"
safe_symlink "$PKG_DIR/.airlock/config" "$HOME/.airlock/config"
safe_symlink "$PKG_DIR/.airlock/image" "$HOME/.airlock/image"

echo "Done."
