#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

shell_files=(
  scripts/install.sh
  scripts/uninstall.sh
  scripts/test.sh
  scripts/test-lint.sh
  scripts/test-unit.sh
  scripts/test-system.sh
  stow/airlock/bin/airlock-build
  stow/airlock/bin/airlock-doctor
  stow/airlock/bin/yolo
  stow/airlock/.airlock/image/entrypoint.sh
)

for file in "${shell_files[@]}"; do
  [[ -f "$file" ]] || fail "missing expected file: $file"
  bash -n "$file"
done
ok "bash syntax: ok"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "${shell_files[@]}"
  ok "shellcheck: ok"
else
  echo "WARN: shellcheck not found; skipping shellcheck lint."
fi

exec_files=(
  scripts/install.sh
  scripts/uninstall.sh
  scripts/test.sh
  scripts/test-lint.sh
  scripts/test-unit.sh
  scripts/test-system.sh
  stow/airlock/bin/airlock-build
  stow/airlock/bin/airlock-doctor
  stow/airlock/bin/yolo
  stow/airlock/.airlock/image/entrypoint.sh
)

for file in "${exec_files[@]}"; do
  [[ -x "$file" ]] || fail "not executable: $file"
done
ok "executables: ok"
