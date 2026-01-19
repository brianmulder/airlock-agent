#!/usr/bin/env bash
set -euo pipefail

if [[ "${AIRLOCK_TIMING:-0}" == "1" ]]; then
  now="$(date -Iseconds 2>/dev/null || true)"
  echo "TIMING: entrypoint start: ${now:-unknown} uid=$(id -u) gid=$(id -g)" >&2
fi

ensure_writable_home() {
  # Some engines/userns modes run as a uid that has no passwd entry in the image, and/or HOME points to a
  # directory owned by root. Ensure git/codex can write dotfiles without touching the host.
  if [[ -n "${HOME:-}" && -d "${HOME:-}" && -w "${HOME:-}" ]]; then
    return 0
  fi
  HOME="/tmp/airlock-home-$(id -u)"
  mkdir -p "$HOME" >/dev/null 2>&1 || true
  export HOME
}

ensure_git_safe_workdir() {
  # Git 2.35+ refuses to operate in repos owned by another UID unless marked safe.
  # In containers (especially rootless userns setups), bind-mounted repos can appear "dubious" even when it's your repo.
  # Make the workspace safe inside the container without touching the host.
  command -v git >/dev/null 2>&1 || return 0

  add_safe_dir() {
    local dir="$1"
    [[ -n "$dir" && -d "$dir" ]] || return 0
    [[ -e "$dir/.git" ]] || return 0

    # Prefer system config when root; otherwise use the user's global config.
    if [[ "$(id -u)" -eq 0 ]]; then
      git config --system --add safe.directory "$dir" >/dev/null 2>&1 || true
    else
      git config --global --add safe.directory "$dir" >/dev/null 2>&1 || true
    fi
  }

  IFS=':' read -r -a dirs <<<"${AIRLOCK_GIT_SAFE_DIRS:-}"
  for dir in "${dirs[@]}"; do
    add_safe_dir "$dir"
  done
}

ensure_user_in_group() {
  local user="$1"
  local group="$2"

  [[ -n "$user" && -n "$group" ]] || return 0
  [[ "$user" != "root" ]] || return 0
  command -v getent >/dev/null 2>&1 || return 0
  command -v usermod >/dev/null 2>&1 || return 0

  if ! getent group "$group" >/dev/null 2>&1; then
    if command -v groupadd >/dev/null 2>&1; then
      groupadd "$group" >/dev/null 2>&1 || true
    fi
  fi

  if getent group "$group" >/dev/null 2>&1; then
    usermod -aG "$group" "$user" >/dev/null 2>&1 || true
  fi
}

group_name_for_gid() {
  local gid="$1"
  [[ -n "$gid" ]] || return 0
  command -v getent >/dev/null 2>&1 || return 0
  getent group | awk -F: -v gid="$gid" '$3 == gid {print $1; exit}'
}

ensure_user_can_access_socket() {
  local user="$1"
  local sock="$2"

  [[ -n "$user" && -n "$sock" ]] || return 0
  [[ "$user" != "root" ]] || return 0
  [[ -S "$sock" ]] || return 0
  command -v usermod >/dev/null 2>&1 || return 0

  local gid group_name created_name
  gid="$(stat -c '%g' "$sock" 2>/dev/null || true)"
  [[ -n "$gid" ]] || return 0

  group_name="$(group_name_for_gid "$gid")"
  if [[ -z "$group_name" ]]; then
    created_name="airlock-sock-$gid"
    if command -v groupadd >/dev/null 2>&1; then
      groupadd -g "$gid" "$created_name" >/dev/null 2>&1 || true
      group_name="$(group_name_for_gid "$gid")"
      [[ -n "$group_name" ]] || group_name="$created_name"
    else
      group_name="$created_name"
    fi
  fi

  usermod -aG "$group_name" "$user" >/dev/null 2>&1 || true
}

start_dind_if_enabled() {
  local run_as_user="$1"

  [[ "${AIRLOCK_DIND:-0}" == "1" ]] || return 0

  if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: AIRLOCK_DIND=1 requires the container to start as root." >&2
    exit 1
  fi

  if [[ "${is_rootless_userns:-0}" == "1" ]]; then
    echo "ERROR: AIRLOCK_DIND=1 is not supported in a rootless user namespace." >&2
    echo "Hint: run yolo with a rootful engine (docker or rootful podman), and avoid userns remapping/rootless engines." >&2
    exit 1
  fi

  local dockerd_bin=""
  for candidate in /usr/sbin/dockerd /usr/bin/dockerd dockerd; do
    if command -v "$candidate" >/dev/null 2>&1; then
      dockerd_bin="$candidate"
      break
    fi
  done

  if [[ -z "$dockerd_bin" ]]; then
    echo "ERROR: dockerd not found in the agent image (need docker.io)." >&2
    exit 1
  fi
  if [[ ! -x /usr/bin/docker ]]; then
    echo "ERROR: docker CLI not found at /usr/bin/docker (need docker.io)." >&2
    exit 1
  fi

  ensure_user_in_group "$run_as_user" docker

  local storage_driver
  local log
  local -a dockerd_args
  local -a extra_args
  local dockerd_pid

  storage_driver="${AIRLOCK_DIND_STORAGE_DRIVER:-vfs}"
  log="${AIRLOCK_DIND_LOG:-/tmp/airlock-dockerd.log}"

  rm -f /var/run/docker.sock >/dev/null 2>&1 || true

  dockerd_args=(
    --host=unix:///var/run/docker.sock
    --storage-driver="$storage_driver"
  )
  if [[ -n "${AIRLOCK_DIND_DOCKERD_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    extra_args=(${AIRLOCK_DIND_DOCKERD_ARGS})
    dockerd_args+=("${extra_args[@]}")
  fi

  "$dockerd_bin" "${dockerd_args[@]}" >"$log" 2>&1 &
  dockerd_pid=$!

  for _ in {1..200}; do
    if /usr/bin/docker version >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$dockerd_pid" >/dev/null 2>&1; then
      echo "ERROR: dockerd exited early; see $log" >&2
      tail -n 80 "$log" >&2 || true
      exit 1
    fi
    sleep 0.1
  done

  echo "ERROR: dockerd did not become ready; see $log" >&2
  tail -n 80 "$log" >&2 || true
  exit 1
}

is_codex_cmd() {
  local cmd="${1:-}"
  [[ "$cmd" == "codex" || "$cmd" == */codex ]]
}

check_codex_config_readable() {
  is_codex_cmd "${1:-}" || return 0
  [[ -n "${CODEX_HOME:-}" ]] || return 0

  local cfg="$CODEX_HOME/config.toml"
  if [[ -e "$cfg" && ! -r "$cfg" ]]; then
    echo "ERROR: codex config not readable: $cfg" >&2
    echo "Hint: this usually means the host ~/.codex was written by another user (often via sudo)." >&2
    echo "Fix on host: sudo chown -R \"\$USER\":\"\$USER\" \"\$HOME/.codex\"" >&2
    exit 1
  fi
}

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

if [[ "$is_rootless_userns" == "1" ]]; then
  echo "ERROR: rootless user namespaces are unsupported." >&2
  echo "Hint: use a rootful engine (docker or rootful podman). Rootless engines commonly fail on UID/GID mappings and networking." >&2
  exit 1
fi

# If we are already running as a non-root user (e.g., engine-level `--user`),
# we cannot create users or chown. Assume the engine/userns already set UID/GID correctly.
if [[ "$current_uid" -ne 0 ]]; then
  start_dind_if_enabled ""

  if [[ "$current_uid" -ne "$TARGET_UID" || "$current_gid" -ne "$TARGET_GID" ]]; then
    echo "ERROR: entrypoint running as uid:gid $current_uid:$current_gid, expected $TARGET_UID:$TARGET_GID" >&2
    echo "Hint: start the container as root so Airlock can map UID/GID, or ensure AIRLOCK_UID/AIRLOCK_GID match the runtime uid:gid." >&2
    exit 1
  fi

  if [[ -z "${HOME:-}" || ! -d "${HOME:-}" ]]; then
    home_from_passwd="$(getent passwd "$current_uid" | cut -d: -f6 || true)"
    export HOME="${home_from_passwd:-/tmp}"
  fi
  check_codex_config_readable "${1:-}"
  ensure_writable_home
  ensure_git_safe_workdir

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

start_dind_if_enabled "$RUN_AS_USER"

# If the host engine socket is bind-mounted into the container, ensure the runtime user can access it.
# (Typical host sockets are root:<group> 0660; the group GID must exist in the container.)
ensure_user_can_access_socket "$RUN_AS_USER" /var/run/docker.sock
ensure_user_can_access_socket "$RUN_AS_USER" /run/podman/podman.sock

# Ensure HOME points to the runtime user
RUN_AS_HOME="$(getent passwd "$RUN_AS_USER" | cut -d: -f6)"
export HOME="${HOME:-$RUN_AS_HOME}"

# Make sure HOME exists and is owned by the runtime user
mkdir -p "$HOME"
chown "$TARGET_UID:$TARGET_GID" "$HOME" >/dev/null 2>&1 || true

check_codex_config_readable "${1:-}"
ensure_git_safe_workdir
exec gosu "$RUN_AS_USER" "$@"
