#!/usr/bin/env bash
set -euo pipefail

TARGET_UID="${AIRLOCK_UID:-1000}"
TARGET_GID="${AIRLOCK_GID:-1000}"
FALLBACK_USER="${AIRLOCK_USER:-airlock}"

current_uid="$(id -u)"
current_gid="$(id -g)"

is_rootless_userns=0
if [[ -r /proc/self/uid_map ]]; then
  # Format: inside_uid outside_uid length
  outside_uid="$(awk 'NR==1 {print $2}' /proc/self/uid_map || true)"
  if [[ -n "$outside_uid" && "$outside_uid" != "0" ]]; then
    is_rootless_userns=1
  fi
fi

# If we are already running as a non-root user (common with podman --userns=keep-id),
# we cannot create users or chown. Assume the engine/userns already set UID/GID correctly.
if [[ "$current_uid" -ne 0 ]]; then
  if [[ "$current_uid" -ne "$TARGET_UID" || "$current_gid" -ne "$TARGET_GID" ]]; then
    echo "ERROR: entrypoint running as uid:gid $current_uid:$current_gid, expected $TARGET_UID:$TARGET_GID" >&2
    echo "Hint: run as root or use an engine userns mode that maps host IDs (e.g., podman --userns=keep-id)." >&2
    exit 1
  fi

  if [[ -z "${HOME:-}" || ! -d "${HOME:-}" ]]; then
    home_from_passwd="$(getent passwd "$current_uid" | cut -d: -f6 || true)"
    export HOME="${home_from_passwd:-/tmp}"
  fi

  exec "$@"
fi

# Root in a rootless user namespace often maps to the host user. In that case, running as root
# avoids mount-permission surprises (container uid 1000 may map to a subuid range).
if [[ "$is_rootless_userns" == "1" && "$TARGET_UID" != "0" ]]; then
  echo "WARN: running as root in a rootless user namespace; skipping UID switch for compatibility." >&2
  mkdir -p "${HOME:-/home/airlock}"
  exec "$@"
fi

# If a user with TARGET_UID already exists (e.g., \"node\" in devcontainer images), use it.
if getent passwd "$TARGET_UID" >/dev/null; then
  RUN_AS_USER="$(getent passwd "$TARGET_UID" | cut -d: -f1)"
else
  # Ensure group exists for TARGET_GID
  if ! getent group "$TARGET_GID" >/dev/null; then
    groupadd -g "$TARGET_GID" "$FALLBACK_USER"
  fi

  # Create user
  useradd -m -u "$TARGET_UID" -g "$TARGET_GID" "$FALLBACK_USER"
  RUN_AS_USER="$FALLBACK_USER"
fi

# Ensure HOME points to the runtime user
RUN_AS_HOME="$(getent passwd "$RUN_AS_USER" | cut -d: -f6)"
export HOME="${HOME:-$RUN_AS_HOME}"

# Make sure HOME exists and is owned by the runtime user
mkdir -p "$HOME"
chown -R "$TARGET_UID:$TARGET_GID" "$HOME" || true

exec gosu "$RUN_AS_USER" "$@"
