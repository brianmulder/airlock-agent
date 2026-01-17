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

if [[ "$INSTALL_MODE" == "stow" ]]; then
  command -v stow >/dev/null 2>&1 || {
    echo "ERROR: stow not found (AIRLOCK_INSTALL_MODE=stow)" >&2
    echo "Hint: sudo apt-get update && sudo apt-get install -y stow" >&2
    exit 1
  }

  echo "--- Uninstalling Airlock via stow ---"
  stow -D -d "$STOW_DIR" -t "$HOME" airlock
  echo "Done."
  exit 0
fi

echo "--- Uninstalling Airlock symlinks (no stow) ---"

safe_unlink() {
  local dst="$1"
  local expected_src="$2"

  if [[ ! -e "$dst" && ! -L "$dst" ]]; then
    return 0
  fi

  if [[ ! -L "$dst" ]]; then
    echo "WARN: not a symlink; skipping: $dst" >&2
    return 0
  fi

  local real_dst real_src
  real_dst="$(readlink -f "$dst" 2>/dev/null || true)"
  real_src="$(readlink -f "$expected_src" 2>/dev/null || true)"

  if [[ -n "$real_dst" && -n "$real_src" && "$real_dst" == "$real_src" ]]; then
    rm -f "$dst"
  else
    echo "WARN: symlink does not match expected target; skipping: $dst" >&2
  fi
}

safe_unlink "$HOME/bin/yolo" "$PKG_DIR/bin/yolo"
safe_unlink "$HOME/bin/airlock-build" "$PKG_DIR/bin/airlock-build"
safe_unlink "$HOME/bin/airlock-doctor" "$PKG_DIR/bin/airlock-doctor"
safe_unlink "$HOME/.airlock/config" "$PKG_DIR/.airlock/config"
safe_unlink "$HOME/.airlock/image" "$PKG_DIR/.airlock/image"

echo "Done."
