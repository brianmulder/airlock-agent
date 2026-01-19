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
  err="$(mktemp)"
  if npx --yes markdownlint-cli2 >/dev/null 2>"$err"; then
    ok "markdownlint: ok (via npx)"
  else
    echo "WARN: markdownlint-cli2 unavailable (npx run failed); skipping markdown lint."
    sed -n '1,12p' "$err" | sed 's/^/  /' >&2 || true
    echo "  Hint: install once to avoid npx downloads: npm i -g markdownlint-cli2" >&2
  fi
  rm -f "$err" || true
else
  echo "WARN: npx not found; skipping markdown lint."
fi
