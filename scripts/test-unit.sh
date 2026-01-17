#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

home_dir="$tmp/home"
context_dir="$tmp/context"
mkdir -p "$home_dir" "$context_dir"

export HOME="$home_dir"

mkdir -p "$HOME/.airlock/policy" "$HOME/.airlock/image"
printf '%s\n' "# test" >"$HOME/.airlock/policy/codex.config.toml"
printf '%s\n' "# test" >"$HOME/.airlock/policy/AGENTS.md"
printf '%s\n' "# test" >"$HOME/.airlock/policy/zshrc"
printf '%s\n' "hello" >"$context_dir/hello.txt"

ok "unit setup"

## config sanity: codex.config.toml is valid TOML
if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import tomllib' >/dev/null 2>&1; then
    python3 - <<'PY'
import pathlib
import tomllib

path = pathlib.Path("stow/airlock/.airlock/policy/codex.config.toml")
tomllib.loads(path.read_text(encoding="utf-8"))
PY
    ok "codex.config.toml parses (python tomllib): ok"
  else
    echo "WARN: python3 tomllib not available; skipping TOML parse check."
  fi
else
  echo "WARN: python3 not found; skipping TOML parse check."
fi

## yolo guardrail: drafts inside context must fail
if AIRLOCK_ENGINE=true \
  AIRLOCK_CONTEXT_DIR="$context_dir" \
  DRAFTS_DIR="$context_dir/drafts" \
  stow/airlock/bin/yolo >/dev/null 2>&1; then
  fail "expected yolo to fail when DRAFTS_DIR is inside AIRLOCK_CONTEXT_DIR"
fi
ok "yolo guardrail: ok"

## yolo dry-run defaults (no host networking; rm enabled)
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_CONTEXT_DIR="$context_dir" \
  DRAFTS_DIR="$HOME/.airlock/outbox/drafts" \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q '^CMD:' || fail "expected yolo dry-run to print CMD:"
printf '%s\n' "$out" | grep -q -- '--rm' || fail "expected yolo to include --rm by default"
printf '%s\n' "$out" | grep -q -- ' bash ' || fail "expected yolo to append command args"
if printf '%s\n' "$out" | grep -q -- '--network host'; then
  fail "expected yolo to NOT use host networking by default"
fi
ok "yolo dry-run defaults: ok"

## yolo: host networking opt-in
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_NETWORK=host \
  AIRLOCK_CONTEXT_DIR="$context_dir" \
  DRAFTS_DIR="$HOME/.airlock/outbox/drafts" \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q -- '--network host' || fail "expected yolo to include --network host"
ok "yolo host networking opt-in: ok"

## yolo: podman defaults userns to keep-id
out="$(
  AIRLOCK_ENGINE=podman \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_CONTEXT_DIR="$context_dir" \
  DRAFTS_DIR="$HOME/.airlock/outbox/drafts" \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q -- '--userns=keep-id' || fail "expected yolo to default podman userns to keep-id"
ok "yolo podman userns default: ok"

## yolo: userns override
out="$(
  AIRLOCK_ENGINE=podman \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_USERNS=private \
  AIRLOCK_CONTEXT_DIR="$context_dir" \
  DRAFTS_DIR="$HOME/.airlock/outbox/drafts" \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q -- '--userns=private' || fail "expected yolo to use AIRLOCK_USERNS override"
ok "yolo userns override: ok"

## yolo: keep container opt-in
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_RM=0 \
  AIRLOCK_CONTEXT_DIR="$context_dir" \
  DRAFTS_DIR="$HOME/.airlock/outbox/drafts" \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
if printf '%s\n' "$out" | grep -q -- '--rm'; then
  fail "expected yolo to omit --rm when AIRLOCK_RM=0"
fi
ok "yolo keep container opt-in: ok"

## airlock-build dry-run (engine configurable)
printf '%s\n' 'FROM debian:bookworm-slim' >"$HOME/.airlock/image/agent.Dockerfile"
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_IMAGE=airlock-agent:test \
  AIRLOCK_BASE_IMAGE=example/base:latest \
  AIRLOCK_CODEX_VERSION=0.0.0 \
  stow/airlock/bin/airlock-build
)"
printf '%s\n' "$out" | grep -q '^CMD:' || fail "expected airlock-build dry-run to print CMD:"
printf '%s\n' "$out" | grep -q -- ' build ' || fail "expected airlock-build to use engine build"
printf '%s\n' "$out" | grep -q -- 'BASE_IMAGE=example/base:latest' || fail "expected BASE_IMAGE build-arg"
printf '%s\n' "$out" | grep -q -- 'CODEX_VERSION=0.0.0' || fail "expected CODEX_VERSION build-arg"
ok "airlock-build dry-run: ok"

## airlock-build: podman defaults isolation to chroot
printf '%s\n' 'FROM debian:bookworm-slim' >"$HOME/.airlock/image/agent.Dockerfile"
out="$(
  AIRLOCK_ENGINE=podman \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_IMAGE=airlock-agent:test \
  AIRLOCK_BASE_IMAGE=example/base:latest \
  AIRLOCK_CODEX_VERSION=0.0.0 \
  stow/airlock/bin/airlock-build
)"
printf '%s\n' "$out" | grep -q -- '--isolation chroot' || fail "expected podman build to default to --isolation chroot"
ok "airlock-build podman isolation default: ok"

## airlock-build: podman isolation override
out="$(
  AIRLOCK_ENGINE=podman \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_BUILD_ISOLATION=oci \
  AIRLOCK_IMAGE=airlock-agent:test \
  AIRLOCK_BASE_IMAGE=example/base:latest \
  AIRLOCK_CODEX_VERSION=0.0.0 \
  stow/airlock/bin/airlock-build
)"
printf '%s\n' "$out" | grep -q -- '--isolation oci' || fail "expected podman build to use AIRLOCK_BUILD_ISOLATION override"
ok "airlock-build podman isolation override: ok"

## airlock-build: pull toggle
out="$(
  AIRLOCK_ENGINE=podman \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_PULL=0 \
  AIRLOCK_IMAGE=airlock-agent:test \
  AIRLOCK_BASE_IMAGE=example/base:latest \
  AIRLOCK_CODEX_VERSION=0.0.0 \
  stow/airlock/bin/airlock-build
)"
printf '%s\n' "$out" | grep -q -- '--pull-never' || fail "expected podman build to use --pull-never when AIRLOCK_PULL=0"
ok "airlock-build pull toggle: ok"

## stow install/uninstall (idempotence + symlinks)
if command -v stow >/dev/null 2>&1; then
  stow_home="$tmp/stow-home"
  mkdir -p "$stow_home/.airlock" "$stow_home/bin"

  stow -d "$REPO_ROOT/stow" -t "$stow_home" airlock
  [[ -d "$stow_home/.airlock" && ! -L "$stow_home/.airlock" ]] || fail "expected .airlock to be a real directory"
  [[ -L "$stow_home/.airlock/policy" ]] || fail "expected stowed policy to be symlinked"
  [[ -L "$stow_home/.airlock/image" ]] || fail "expected stowed image to be symlinked"
  [[ -L "$stow_home/bin/yolo" ]] || fail "expected stowed yolo to be a symlink"
  [[ -e "$stow_home/.airlock/policy/codex.config.toml" ]] || fail "expected codex config to exist under stowed policy"

  stow -d "$REPO_ROOT/stow" -t "$stow_home" airlock
  ok "stow idempotence: ok"

  stow -D -d "$REPO_ROOT/stow" -t "$stow_home" airlock
  [[ -d "$stow_home/bin" ]] || fail "expected bin directory to remain after uninstall"
  [[ -d "$stow_home/.airlock" ]] || fail "expected .airlock directory to remain after uninstall"
  [[ ! -e "$stow_home/bin/yolo" ]] || fail "expected yolo removed after uninstall"
  [[ ! -e "$stow_home/.airlock/policy" ]] || fail "expected policy symlink removed after uninstall"
  [[ ! -e "$stow_home/.airlock/image" ]] || fail "expected image symlink removed after uninstall"
  ok "stow uninstall: ok"
else
  echo "WARN: stow not found; skipping stow unit tests."
fi

ok "unit tests: complete"
