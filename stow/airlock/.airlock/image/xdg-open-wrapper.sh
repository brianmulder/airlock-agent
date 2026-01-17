#!/usr/bin/env bash
set -euo pipefail

# Minimal xdg-open shim for headless/yolo containers.
#
# Some CLIs (including OpenCode) try to open auth URLs using `xdg-open`. In a container without a desktop
# environment, this fails and can block auth. Prefer a best-effort open when a GUI is available; otherwise
# print the target so the user can open it on the host.

target="${1:-}"
if [[ -z "$target" ]]; then
  exit 0
fi

log_line() {
  local msg="$1"

  # Some callers spawn xdg-open with stdio closed/ignored. Prefer writing to the controlling TTY so the
  # user can still see the URL in a TUI.
  if [[ -w /dev/tty ]]; then
    printf '%s\n' "$msg" >/dev/tty
    return 0
  fi

  printf '%s\n' "$msg" >&2
}

if command -v /usr/bin/xdg-open >/dev/null 2>&1; then
  if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    if /usr/bin/xdg-open "$@" >/dev/null 2>&1; then
      exit 0
    fi
  fi
fi

log_line "AIRLOCK: open this on the host:"
log_line "$target"

# Persist the most recent URL for headless flows where the caller doesn't show it.
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/airlock" >/dev/null 2>&1 || true
printf '%s\n' "$target" >"${XDG_CACHE_HOME:-$HOME/.cache}/airlock/last-url.txt" 2>/dev/null || true
exit 0
