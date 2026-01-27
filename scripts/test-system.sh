#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

image_exists() {
  local image="$1"
  "$AIRLOCK_ENGINE" image inspect "$image" >/dev/null 2>&1
}

image_input_sha() {
  local dir="$1"
  local -a hash_cmd
  if command -v sha256sum >/dev/null 2>&1; then
    hash_cmd=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    hash_cmd=(shasum -a 256)
  else
    echo "unknown"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  find "$dir" -type f -print0 | LC_ALL=C sort -z | xargs -0 "${hash_cmd[@]}" >"$tmp"
  "${hash_cmd[@]}" "$tmp" | awk '{print $1}'
  rm -f "$tmp" || true
}

image_label() {
  local image="$1"
  local label="$2"
  # Try docker/nerdctl layout first, then podman layout.
  "$AIRLOCK_ENGINE" image inspect "$image" --format "{{ index .Config.Labels \"$label\" }}" 2>/dev/null || \
    "$AIRLOCK_ENGINE" image inspect "$image" -f "{{ index .Labels \"$label\" }}" 2>/dev/null || \
    true
}

pick_engine() {
  local engine
  for engine in podman docker nerdctl; do
    if ! command -v "$engine" >/dev/null 2>&1; then
      continue
    fi
    # Best-effort: prefer a reachable, non-rootless engine.
    if ! "$engine" info >/dev/null 2>&1; then
      continue
    fi

    # Airlock targets rootful engines. Rootless engines commonly fail on UID/GID mappings and/or networking.
    if "$engine" info 2>/dev/null | awk 'tolower($1)=="rootless:" {print tolower($2); exit}' | grep -qx true; then
      continue
    fi

      echo "$engine"
      return 0
  done
  return 1
}

AIRLOCK_ENGINE="${AIRLOCK_ENGINE:-}"
if [[ -z "$AIRLOCK_ENGINE" ]]; then
  AIRLOCK_ENGINE="$(pick_engine || true)"
fi

if ! command -v stow >/dev/null 2>&1; then
  echo "SKIP: stow not found; system smoke test requires stow."
  exit 0
fi

if ! command -v "$AIRLOCK_ENGINE" >/dev/null 2>&1; then
  if [[ -z "${AIRLOCK_ENGINE:-}" ]]; then
    echo "SKIP: no supported engine found (need docker/rootful podman/nerdctl)."
  else
    echo "SKIP: engine not found: ${AIRLOCK_ENGINE:-<unset>}"
  fi
  exit 0
fi

tmp=""
if [[ "${AIRLOCK_YOLO:-0}" == "1" ]]; then
  tmp_base="$REPO_ROOT/.airlock-test-tmp"
  mkdir -p "$tmp_base"
  tmp="$(mktemp -d -p "$tmp_base")"
else
  tmp="$(mktemp -d)"
fi
cleanup() {
  if [[ -n "${AIRLOCK_CONTAINER_NAME:-}" ]]; then
    "$AIRLOCK_ENGINE" rm -f "$AIRLOCK_CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
  if [[ "${AIRLOCK_SYSTEM_CLEAN_IMAGE:-0}" == "1" && "${did_build:-0}" == "1" && -n "${AIRLOCK_IMAGE:-}" ]]; then
    "$AIRLOCK_ENGINE" image rm "$AIRLOCK_IMAGE" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

engine_info_err="$tmp/engine-info.err"
if ! "$AIRLOCK_ENGINE" info >/dev/null 2>"$engine_info_err"; then
  echo "SKIP: engine not reachable: $AIRLOCK_ENGINE"
  sed -n '1,25p' "$engine_info_err" | sed 's/^/  /' >&2 || true
  exit 0
fi

if "$AIRLOCK_ENGINE" info 2>/dev/null | awk 'tolower($1)=="rootless:" {print tolower($2); exit}' | grep -qx true; then
  echo "SKIP: rootless engine not supported (set AIRLOCK_ENGINE=docker or use a rootful engine): $AIRLOCK_ENGINE"
  exit 0
fi

home_dir="$tmp/home"
ro_dir="$tmp/ro"
rw_dir="$tmp/rw"
work_dir="$tmp/work"
mkdir -p "$home_dir" "$ro_dir" "$rw_dir" "$work_dir"

printf '%s\n' "hello from ro" >"$ro_dir/hello.txt"
printf '%s\n' "hello from work" >"$work_dir/README.txt"

if command -v git >/dev/null 2>&1; then
  git -C "$work_dir" init -q
  git -C "$work_dir" config user.email "airlock@example.invalid"
  git -C "$work_dir" config user.name "Airlock Smoke"
  git -C "$work_dir" add README.txt
  git -C "$work_dir" commit -q -m "init"
else
  echo "WARN: git not found; skipping git smoke assertion."
fi

mkdir -p "$home_dir/.airlock" "$home_dir/bin"
stow -d "$REPO_ROOT/stow" -t "$home_dir" airlock

export HOME="$home_dir"
export PATH="$HOME/bin:$PATH"

default_existing_image="airlock-agent:local"

if [[ -z "${AIRLOCK_IMAGE:-}" ]]; then
  export AIRLOCK_IMAGE="$default_existing_image"
fi

export AIRLOCK_ENGINE
export AIRLOCK_TTY=0
export AIRLOCK_RM=0
export AIRLOCK_CONTAINER_NAME="airlock-smoke-${RANDOM}${RANDOM}"
unset AIRLOCK_MOUNT_STYLE

ok "system setup"

need_build=0
if [[ "${AIRLOCK_SYSTEM_REBUILD:-0}" == "1" ]]; then
  need_build=1
elif ! image_exists "$AIRLOCK_IMAGE"; then
  need_build=1
fi

did_build=0
if [[ "$need_build" == "1" ]]; then
  base_image="$(awk '/^ARG BASE_IMAGE=/{sub(/^ARG BASE_IMAGE=/,""); print; exit}' "$HOME/.airlock/image/agent.Dockerfile" || true)"
  if [[ -z "$base_image" ]]; then
    fail "unable to determine default BASE_IMAGE from agent.Dockerfile"
  fi

  if [[ "${AIRLOCK_PULL:-1}" == "0" ]]; then
    if ! "$AIRLOCK_ENGINE" image inspect "$base_image" >/dev/null 2>&1; then
      echo "SKIP: base image not present locally and AIRLOCK_PULL=0: $base_image"
      exit 0
    fi
  fi

  airlock-build
  did_build=1
  ok "image built: $AIRLOCK_IMAGE"
else
  ctx_sha="$(image_input_sha "$HOME/.airlock/image")"
  img_sha="$(image_label "$AIRLOCK_IMAGE" "io.airlock.image_input_sha")"
  if [[ -n "$ctx_sha" && "$ctx_sha" != "unknown" && ( -z "$img_sha" || "$img_sha" == "unknown" || "$ctx_sha" != "$img_sha" ) ]]; then
    ok "existing image is stale; rebuilding: $AIRLOCK_IMAGE"
    AIRLOCK_IMAGE_INPUT_SHA="$ctx_sha" airlock-build
    did_build=1
    ok "image built: $AIRLOCK_IMAGE"
  else
    ok "using existing image: $AIRLOCK_IMAGE"
  fi
fi

pushd "$work_dir" >/dev/null

host_ro="$ro_dir"
host_rw="$rw_dir"
if [[ "${AIRLOCK_YOLO:-0}" == "1" && "$host_ro" == /host/* ]]; then
  host_ro="${host_ro#/host}"
fi
if [[ "${AIRLOCK_YOLO:-0}" == "1" && "$host_rw" == /host/* ]]; then
  host_rw="${host_rw#/host}"
fi

ro_target="$host_ro"
rw_target="$host_rw"

smoke_script="$(cat <<EOS
set -euo pipefail

RO_TARGET="$ro_target"
RW_TARGET="$rw_target"

test -f "\${RO_TARGET}/hello.txt"
test -f "\$(pwd)/README.txt"

# RW mounts
touch "\$(pwd)/.airlock-smoke-work"
touch "\${RW_TARGET}/.airlock-smoke-rw"

# RO mount
if touch "\${RO_TARGET}/.airlock-smoke-ro" 2>/dev/null; then
  echo "ERROR: ro mount is writable"
  exit 1
fi

# Mount presence
grep -Fq " \${RO_TARGET} " /proc/mounts
grep -Fq " \${RW_TARGET} " /proc/mounts

# Basic network config (bridge by default; don't assert internet access)
ip route | grep -q "^default "

# Git should work even if the container user differs from the repo owner (safe.directory set inside container)
if command -v git >/dev/null 2>&1 && test -e "\$(pwd)/.git"; then
  git -C "\$(pwd)" status --porcelain >/dev/null
fi

# Container engine passthrough (optional): if the socket is mounted, the engine should be usable inside yolo.
if command -v podman >/dev/null 2>&1 && test -S /run/podman/podman.sock; then
  podman version >/dev/null
  podman ps >/dev/null
fi
EOS
)"

# When running the system test from inside a `yolo` container, the engine is typically remote (host socket),
# so re-mounting the engine socket into the inner container is not meaningful and can fail due to path mismatch.
set +e
out="$(
  AIRLOCK_MOUNT_ENGINE_SOCKET=0 yolo --mount-ro "$ro_dir" --add-dir "$rw_dir" -- bash -c "$smoke_script" 2>&1
)"
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  if printf '%s\n' "$out" | grep -qiE 'rootless user namespaces are unsupported'; then
    echo "SKIP: rootless user namespaces are unsupported (use a rootful engine): $AIRLOCK_ENGINE"
    printf '%s\n' "$out" | sed -n '1,60p' | sed 's/^/  /' >&2 || true
    exit 0
  fi

  echo "ERROR: yolo smoke run failed (see output):" >&2
  printf '%s\n' "$out" | sed -n '1,120p' | sed 's/^/  /' >&2 || true
  exit 1
fi

popd >/dev/null
ok "container smoke checks: ok"

if [[ "$AIRLOCK_ENGINE" == "docker" ]]; then
  mode="$("$AIRLOCK_ENGINE" inspect -f '{{.HostConfig.NetworkMode}}' "$AIRLOCK_CONTAINER_NAME")"
  case "$mode" in
    default|bridge) ok "network mode: $mode" ;;
    *) fail "unexpected docker network mode: $mode" ;;
  esac
else
  ok "network mode: not asserted for AIRLOCK_ENGINE=$AIRLOCK_ENGINE"
fi

ok "system smoke test: complete"
