#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

AIRLOCK_ENGINE="${AIRLOCK_ENGINE:-docker}"

if ! command -v stow >/dev/null 2>&1; then
  echo "SKIP: stow not found; system smoke test requires stow."
  exit 0
fi

if ! command -v "$AIRLOCK_ENGINE" >/dev/null 2>&1; then
  echo "SKIP: engine not found: $AIRLOCK_ENGINE"
  exit 0
fi

if ! "$AIRLOCK_ENGINE" info >/dev/null 2>&1; then
  echo "SKIP: engine not reachable: $AIRLOCK_ENGINE"
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

home_dir="$tmp/home"
context_dir="$tmp/context"
work_dir="$tmp/work"
mkdir -p "$home_dir" "$context_dir" "$work_dir"

printf '%s\n' "hello from context" >"$context_dir/hello.txt"
printf '%s\n' "hello from work" >"$work_dir/README.txt"

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

# UID mapping sanity (host UID injected via AIRLOCK_UID)
test "$(id -u)" = "${AIRLOCK_UID}"
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
