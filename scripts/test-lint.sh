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
  scripts/test-system-dind.sh
  scripts/venv.sh
  stow/airlock/bin/airlock
  stow/airlock/bin/airlock-config
  stow/airlock/bin/airlock-build
  stow/airlock/bin/airlock-doctor
  stow/airlock/bin/airlock-wsl-prereqs
  stow/airlock/bin/yolo
  stow/airlock/.airlock/image/entrypoint.sh
  stow/airlock/.airlock/image/podman-wrapper.sh
  stow/airlock/.airlock/image/docker-wrapper.sh
  stow/airlock/.airlock/image/xdg-open-wrapper.sh
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
  scripts/test-system-dind.sh
  scripts/venv.sh
  stow/airlock/bin/airlock
  stow/airlock/bin/airlock-config
  stow/airlock/bin/airlock-build
  stow/airlock/bin/airlock-doctor
  stow/airlock/bin/airlock-wsl-prereqs
  stow/airlock/bin/yolo
  stow/airlock/.airlock/image/entrypoint.sh
  stow/airlock/.airlock/image/podman-wrapper.sh
  stow/airlock/.airlock/image/docker-wrapper.sh
  stow/airlock/.airlock/image/xdg-open-wrapper.sh
)

for file in "${exec_files[@]}"; do
  [[ -x "$file" ]] || fail "not executable: $file"
done
ok "executables: ok"

if command -v markdownlint-cli2 >/dev/null 2>&1; then
  markdownlint-cli2
  ok "markdownlint: ok"
elif [[ "${AIRLOCK_OFFLINE:-0}" != "0" ]]; then
  echo "WARN: AIRLOCK_OFFLINE=1 set; skipping markdown lint (would require network via npx)."
elif command -v npx >/dev/null 2>&1; then
  # Use npx as a hermetic runner: no global install required, and it uses npm cache between runs.
  # If markdownlint finds issues, this should fail the lint step (don't hide signals).
  npx --yes markdownlint-cli2
  ok "markdownlint: ok (via npx)"
else
  fail "markdownlint-cli2 not found and npx unavailable (install markdownlint-cli2 or ensure npx is present)"
fi
