#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

pick_engine() {
  local engine
  for engine in podman docker nerdctl; do
    if command -v "$engine" >/dev/null 2>&1; then
      echo "$engine"
      return 0
    fi
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
  echo "SKIP: engine not found: ${AIRLOCK_ENGINE:-<unset>}"
  exit 0
fi

tmp="$(mktemp -d)"
cleanup() {
  if [[ -n "${AIRLOCK_CONTAINER_NAME:-}" ]]; then
    "$AIRLOCK_ENGINE" rm -f "$AIRLOCK_CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
  if [[ -n "${AIRLOCK_IMAGE:-}" ]]; then
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

home_dir="$tmp/home"
context_dir="$tmp/context"
work_dir="$tmp/work"
mkdir -p "$home_dir" "$context_dir" "$work_dir"

printf '%s\n' "hello from context" >"$context_dir/hello.txt"
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

export AIRLOCK_IMAGE="airlock-agent:smoke-${RANDOM}${RANDOM}"
export AIRLOCK_CONTEXT_DIR="$context_dir"
export AIRLOCK_ENGINE
export AIRLOCK_TTY=0
export AIRLOCK_RM=0
export AIRLOCK_CONTAINER_NAME="airlock-smoke-${RANDOM}${RANDOM}"

ok "system setup"

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
ok "image built: $AIRLOCK_IMAGE"

pushd "$work_dir" >/dev/null

smoke_script="$(cat <<'EOS'
set -euo pipefail

test -f /context/hello.txt
test -f /work/README.txt

# RW mounts
touch /work/.airlock-smoke-work
touch /drafts/.airlock-smoke-drafts

# RO mount
if touch /context/.airlock-smoke-context 2>/dev/null; then
  echo "ERROR: /context is writable"
  exit 1
fi

# Mount presence
grep -q " /context " /proc/mounts
grep -q " /work " /proc/mounts
grep -q " /drafts " /proc/mounts

# Basic network config (bridge by default; don't assert internet access)
ip route | grep -q "^default "

# UID mapping sanity:
# - In Docker runs we expect id -u == AIRLOCK_UID.
# - In some rootless userns setups (Podman keep-id), the process can run as uid 0 but map to a nonzero host uid.
uid="$(id -u)"
if test "$uid" = "${AIRLOCK_UID}"; then
  true
elif test "$uid" = "0" && test -r /proc/self/uid_map; then
  outside_uid="$(awk 'NR==1 {print $2}' /proc/self/uid_map || true)"
  test -n "$outside_uid" && test "$outside_uid" != "0"
else
  echo "ERROR: unexpected uid mapping: uid=$uid (expected ${AIRLOCK_UID} or rootless-userns root)" >&2
  exit 1
fi

# Git should work even if the container user differs from the repo owner (safe.directory set inside container)
if command -v git >/dev/null 2>&1 && test -e /work/.git; then
  git -C /work status --porcelain >/dev/null
fi
EOS
)"

yolo -- bash -lc "$smoke_script"

popd >/dev/null
ok "container smoke checks: ok"

if [[ "$AIRLOCK_ENGINE" == "docker" ]]; then
  mode="$("$AIRLOCK_ENGINE" inspect -f '{{.HostConfig.NetworkMode}}' "$AIRLOCK_CONTAINER_NAME")"
  case "$mode" in
    default|bridge) ok "network mode: $mode" ;;
    *) fail "unexpected docker network mode: $mode" ;;
  esac
else
  echo "NOTE: network-mode inspection currently only asserted for AIRLOCK_ENGINE=docker."
fi

ok "system smoke test: complete"
