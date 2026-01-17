#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

home_dir="$tmp/home"
ro_dir="$tmp/ro"
rw_dir="$tmp/rw"
mkdir -p "$home_dir" "$ro_dir" "$rw_dir"

export HOME="$home_dir"

mkdir -p "$HOME/.airlock/policy" "$HOME/.airlock/image"
printf '%s\n' "# test" >"$HOME/.airlock/policy/codex.config.toml"
printf '%s\n' "# test" >"$HOME/.airlock/policy/zshrc"
printf '%s\n' "hello" >"$ro_dir/hello.txt"

ok "unit setup"

## config sanity: codex.config.toml is valid TOML (use repo venv, no system python changes)
./scripts/venv.sh
PYTHON="${AIRLOCK_VENV_DIR:-$REPO_ROOT/.venv}/bin/python"

"$PYTHON" - <<'PY'
import pathlib
import tomllib

path = pathlib.Path("stow/airlock/.airlock/policy/codex.config.toml")
config = tomllib.loads(path.read_text(encoding="utf-8"))
PY
ok "codex.config.toml parses (tomllib): ok"

## yolo dry-run defaults (no host networking; rm enabled)
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q '^CMD:' || fail "expected yolo dry-run to print CMD:"
printf '%s\n' "$out" | grep -q -- '--rm' || fail "expected yolo to include --rm by default"
printf '%s\n' "$out" | grep -q -- ' bash ' || fail "expected yolo to append command args"
printf '%s\n' "$out" | grep -q -- 'AIRLOCK_YOLO=1' || fail "expected yolo to set AIRLOCK_YOLO=1"
if printf '%s\n' "$out" | grep -q -- 'AIRLOCK_CONTEXT='; then
  fail "expected yolo to NOT set AIRLOCK_CONTEXT"
fi
if printf '%s\n' "$out" | grep -q -- 'AIRLOCK_DRAFTS='; then
  fail "expected yolo to NOT set AIRLOCK_DRAFTS"
fi
if printf '%s\n' "$out" | grep -q -- '--network host'; then
  fail "expected yolo to NOT use host networking by default"
fi
printf '%s\n' "$out" | grep -q -- "-v $HOME/.codex:/home/airlock/.codex:rw" || fail "expected yolo to mount host ~/.codex by default"
if printf '%s\n' "$out" | grep -q -- '/home/airlock/.codex/config.toml:ro'; then
  fail "expected yolo to NOT mount policy config.toml by default"
fi
ok "yolo dry-run defaults: ok"

## yolo: host networking opt-in
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_NETWORK=host \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q -- '--network host' || fail "expected yolo to include --network host"
ok "yolo host networking opt-in: ok"

## yolo: podman defaults userns to keep-id (when supported by the CLI)
fakebin_podman="$tmp/fakebin-podman"
mkdir -p "$fakebin_podman"
cat >"$fakebin_podman/podman" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "run" && "${2:-}" == "--help" ]]; then
  echo "  --userns=keep-id    Keep host UID/GID"
  exit 0
fi

exit 0
SH
chmod +x "$fakebin_podman/podman"

out="$(
  PATH="$fakebin_podman:$PATH" \
  AIRLOCK_ENGINE=podman \
  AIRLOCK_DRY_RUN=1 \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q -- '--userns=keep-id' || fail "expected yolo to default podman userns to keep-id when supported"
ok "yolo podman userns default: ok"

## yolo: docker defaults to running as host uid:gid (prevents root-owned bind mount files)
fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
cat >"$fakebin/docker" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fakebin/docker"

out="$(
  PATH="$fakebin:$PATH" \
  AIRLOCK_ENGINE=docker \
  AIRLOCK_DRY_RUN=1 \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q -- "--user $(id -u):$(id -g)" || fail "expected yolo to include --user uid:gid for docker by default"
ok "yolo docker user default: ok"

## yolo: userns override
out="$(
  AIRLOCK_ENGINE=podman \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_USERNS=private \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q -- '--userns=private' || fail "expected yolo to use AIRLOCK_USERNS override"
ok "yolo userns override: ok"

## yolo: keep container opt-in
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_RM=0 \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
if printf '%s\n' "$out" | grep -q -- '--rm'; then
  fail "expected yolo to omit --rm when AIRLOCK_RM=0"
fi
ok "yolo keep container opt-in: ok"

## yolo: if container name is already running, attach instead of failing
fakebin_attach="$tmp/fakebin-attach"
mkdir -p "$fakebin_attach"
cat >"$fakebin_attach/podman" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

subcmd="${1:-}"
shift || true

case "$subcmd" in
  inspect)
    if [[ "${1:-}" == "-f" ]]; then
      # Called as: inspect -f '{{.State.Running}}' <name>
      echo "true"
      exit 0
    fi
    exit 0
    ;;
  exec)
    echo "FAKE_ENGINE: exec $*" >&2
    exit 0
    ;;
  run)
    echo "FAKE_ENGINE: run called unexpectedly" >&2
    exit 42
    ;;
  rm)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SH
chmod +x "$fakebin_attach/podman"

out="$(
  PATH="$fakebin_attach:$PATH" \
  AIRLOCK_ENGINE=podman \
  AIRLOCK_CONTAINER_NAME=airlock-test-attach \
  AIRLOCK_MOUNT_ENGINE_SOCKET=0 \
  stow/airlock/bin/yolo -- bash -lc 'echo ok' 2>&1
)"
printf '%s\n' "$out" | grep -q 'INFO: container is already running; attaching:' || fail "expected yolo to attach when the container name is already running"
printf '%s\n' "$out" | grep -q 'FAKE_ENGINE: exec ' || fail "expected yolo to exec into the running container"
ok "yolo attach to running container: ok"

## yolo: --new starts a second container instead of attaching
fakebin_new="$tmp/fakebin-new"
mkdir -p "$fakebin_new"
cat >"$fakebin_new/podman" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

subcmd="${1:-}"
shift || true

case "$subcmd" in
  inspect)
    if [[ "${1:-}" == "-f" ]]; then
      echo "true"
      exit 0
    fi
    exit 0
    ;;
  run)
    echo "FAKE_ENGINE: run $*" >&2
    exit 0
    ;;
  exec)
    echo "FAKE_ENGINE: exec called unexpectedly" >&2
    exit 42
    ;;
  rm)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SH
chmod +x "$fakebin_new/podman"

out="$(
  PATH="$fakebin_new:$PATH" \
  AIRLOCK_ENGINE=podman \
  AIRLOCK_CONTAINER_NAME=airlock-test-new \
  AIRLOCK_MOUNT_ENGINE_SOCKET=0 \
  stow/airlock/bin/yolo --new -- bash -lc 'echo ok' 2>&1
)"
printf '%s\n' "$out" | grep -q 'INFO: name already in use; starting new container:' || fail "expected yolo --new to choose a new container name when the default is already running"
printf '%s\n' "$out" | grep -q 'FAKE_ENGINE: run ' || fail "expected yolo --new to start a new container (run)"
printf '%s\n' "$out" | grep -q -- '--name airlock-test-new-' || fail "expected yolo --new to append a unique suffix to the container name"
ok "yolo --new starts a second container: ok"

## yolo: Airlock-managed Codex state opt-in (policy overrides mounted ro)
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_CODEX_HOME_MODE=airlock \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q -- "-v $HOME/.airlock/codex-state:/home/airlock/.codex:rw" || fail "expected yolo to mount ~/.airlock/codex-state when AIRLOCK_CODEX_HOME_MODE=airlock"
printf '%s\n' "$out" | grep -q -- '/home/airlock/.codex/config.toml:ro' || fail "expected yolo to mount policy config.toml ro when AIRLOCK_CODEX_HOME_MODE=airlock"
if printf '%s\n' "$out" | grep -q -- '/home/airlock/.codex/AGENTS.md:ro'; then
  fail "expected yolo to NOT mount a policy AGENTS.md (use host ~/.codex/AGENTS.md instead)"
fi
ok "yolo airlock codex home opt-in: ok"

## yolo: extra dirs (ro + rw mounts); forwards rw mounts to codex --add-dir
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  stow/airlock/bin/yolo --mount-ro "$ro_dir" --add-dir "$rw_dir" -- codex --profile yolo --help
)"
printf '%s\n' "$out" | grep -q -- "-v $ro_dir:/host$ro_dir:ro" || fail "expected yolo --mount-ro to bind-mount ro"
printf '%s\n' "$out" | grep -q -- "-v $rw_dir:/host$rw_dir:rw" || fail "expected yolo --add-dir to bind-mount rw"
printf '%s\n' "$out" | grep -q -- " codex " || fail "expected yolo to run codex"
printf '%s\n' "$out" | grep -q -- "--add-dir /host$rw_dir" || fail "expected yolo to inject codex --add-dir for rw mount"
if printf '%s\n' "$out" | grep -q -- "--add-dir /host$ro_dir"; then
  fail "expected yolo to NOT inject codex --add-dir for ro mount"
fi
ok "yolo extra dirs + codex injection: ok"

## yolo: codex fails fast if host ~/.codex/config.toml is unreadable
# Note: this is only meaningful when running as a non-root user; root can read 000 files.
if [[ "$(id -u)" -eq 0 ]]; then
  ok "yolo unreadable host config guard: n/a (running as root)"
else
  mkdir -p "$HOME/.codex"
  printf '%s\n' "# test" >"$HOME/.codex/config.toml"
  chmod 000 "$HOME/.codex/config.toml"

  set +e
  out="$(
    AIRLOCK_ENGINE=true \
    AIRLOCK_DRY_RUN=1 \
    stow/airlock/bin/yolo -- codex --help 2>&1
  )"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "expected yolo to exit non-zero when host ~/.codex/config.toml is unreadable"
  printf '%s\n' "$out" | grep -q 'ERROR: host Codex config not readable' || fail "expected yolo to print an actionable error for unreadable host codex config"

  chmod 600 "$HOME/.codex/config.toml"
  ok "yolo unreadable host config guard: ok"
fi

## yolo: if run from a git subdir, mount repo root so `.git/` is available
if command -v git >/dev/null 2>&1; then
  workrepo="$tmp/workrepo"
  mkdir -p "$workrepo"
  git -C "$workrepo" init -q
  git -C "$workrepo" config user.email "airlock@example.invalid"
  git -C "$workrepo" config user.name "Airlock Test"
  printf '%s\n' "hello" >"$workrepo/README.md"
  git -C "$workrepo" add README.md
  git -C "$workrepo" commit -q -m "init"

  mkdir -p "$workrepo/sub/dir"
  pushd "$workrepo/sub/dir" >/dev/null
  out="$(
    AIRLOCK_ENGINE=true \
    AIRLOCK_DRY_RUN=1 \
    "$REPO_ROOT/stow/airlock/bin/yolo" -- bash -lc 'echo ok'
  )"
  popd >/dev/null

  printf '%s\n' "$out" | grep -q -- "-v $workrepo:/host$workrepo:rw" || fail "expected yolo to mount git repo root at canonical /host path"
  printf '%s\n' "$out" | grep -q -- "-w /host$workrepo/sub/dir" || fail "expected yolo to set canonical workdir to subdir within mounted repo"
  ok "yolo git-root mount: ok"
else
  echo "WARN: git not found; skipping git-root mount unit test."
fi

## airlock-build dry-run (engine configurable)
printf '%s\n' 'FROM debian:bookworm-slim' >"$HOME/.airlock/image/agent.Dockerfile"
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_IMAGE=airlock-agent:test \
  AIRLOCK_BASE_IMAGE=example/base:latest \
  AIRLOCK_CODEX_VERSION=0.0.0 \
  AIRLOCK_NPM_VERSION=9.9.9 \
  stow/airlock/bin/airlock-build
)"
printf '%s\n' "$out" | grep -q '^CMD:' || fail "expected airlock-build dry-run to print CMD:"
printf '%s\n' "$out" | grep -q -- ' build ' || fail "expected airlock-build to use engine build"
printf '%s\n' "$out" | grep -q -- 'BASE_IMAGE=example/base:latest' || fail "expected BASE_IMAGE build-arg"
printf '%s\n' "$out" | grep -q -- 'CODEX_VERSION=0.0.0' || fail "expected CODEX_VERSION build-arg"
printf '%s\n' "$out" | grep -q -- 'NPM_VERSION=9.9.9' || fail "expected NPM_VERSION build-arg"
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
