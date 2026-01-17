#!/usr/bin/env bash
set -euo pipefail

# Prefer a real Docker CLI when available (e.g., when talking to a mounted docker.sock).
# Otherwise, fall back to `podman` (which in Airlock prefers the host socket when mounted).

if command -v /usr/bin/docker >/dev/null 2>&1; then
  exec /usr/bin/docker "$@"
fi

exec podman "$@"
