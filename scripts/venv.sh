#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${AIRLOCK_VENV_DIR:-$REPO_ROOT/.venv}"

if [[ -x "$VENV_DIR/bin/python" ]]; then
  exit 0
fi

PYTHON_BIN="${AIRLOCK_PYTHON_BIN:-}"
if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3.11 >/dev/null 2>&1; then
    PYTHON_BIN="python3.11"
  else
    PYTHON_BIN="python3"
  fi
fi

command -v "$PYTHON_BIN" >/dev/null 2>&1 || fail "python not found: $PYTHON_BIN"

if ! "$PYTHON_BIN" -c 'import sys; assert sys.version_info >= (3, 11)' >/dev/null 2>&1; then
  fail "python must be 3.11+ to provide tomllib; install python3.11-venv and set AIRLOCK_PYTHON_BIN=python3.11"
fi

"$PYTHON_BIN" -m venv "$VENV_DIR"
