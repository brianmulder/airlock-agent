#!/usr/bin/env bash
set -euo pipefail

TARGET_UID="${AIRLOCK_UID:-1000}"
TARGET_GID="${AIRLOCK_GID:-1000}"
FALLBACK_USER="${AIRLOCK_USER:-airlock}"

# If a user with TARGET_UID already exists (e.g., "node" in devcontainer images), use it.
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

# Execute the requested command as the runtime user
exec gosu "$RUN_AS_USER" "$@"
