#!/usr/bin/env bash
set -euo pipefail

# Prefer talking to the host engine via a mounted socket (docker-outside-of-docker).
# If the socket isn't present, fall back to local podman (may fail depending on permissions).

SOCK_PATH="${AIRLOCK_PODMAN_SOCK_PATH:-/run/podman/podman.sock}"

if [[ -S "$SOCK_PATH" ]]; then
  # Many hosts run an older Podman service than the distro Podman client inside the image.
  # For common workflows (build/run/ps/...), prefer the Docker-compatible API via `docker`,
  # which is generally more tolerant of client/server version skew.
  if [[ -z "${DOCKER_HOST:-}" ]]; then
    export DOCKER_HOST="unix://$SOCK_PATH"
  fi

  case "${1:-}" in
    build|run|pull|push|images|image|ps|rmi|rm|exec|logs|inspect|version|info|login|logout|tag)
      exec docker "$@"
      ;;
  esac

  if command -v /usr/bin/podman-remote >/dev/null 2>&1; then
    exec /usr/bin/podman-remote --url "unix://$SOCK_PATH" "$@"
  fi
  exec /usr/bin/podman --remote --url "unix://$SOCK_PATH" "$@"
fi

exec /usr/bin/podman "$@"
