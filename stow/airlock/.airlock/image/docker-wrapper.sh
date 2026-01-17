#!/usr/bin/env bash
set -euo pipefail

# Prefer a real Docker CLI when usable (e.g., when talking to a mounted docker.sock or explicit DOCKER_HOST).
# Otherwise, fall back to `podman` (which in Airlock prefers the host socket when mounted).

if command -v /usr/bin/docker >/dev/null 2>&1; then
  if [[ -n "${DOCKER_HOST:-}" ]]; then
    exec /usr/bin/docker "$@"
  fi

  if [[ -S /var/run/docker.sock ]]; then
    exec /usr/bin/docker "$@"
  fi
fi

exec podman "$@"
