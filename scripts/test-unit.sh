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

# Unit tests should be engine-free and must not depend on the caller's environment (e.g., `AIRLOCK_ENGINE=docker`).
unset \
  AIRLOCK_ADD_DIRS \
  AIRLOCK_BUILD_ISOLATION \
  AIRLOCK_BUILD_USERNS \
  AIRLOCK_CODEX_VERSION \
  AIRLOCK_CONFIG_DIR \
  AIRLOCK_CONFIG_TOML \
  AIRLOCK_CONTAINER_NAME \
  AIRLOCK_DIND \
  AIRLOCK_DIND_DOCKERD_ARGS \
  AIRLOCK_DIND_STORAGE_DRIVER \
  AIRLOCK_DRY_RUN \
  AIRLOCK_EDITOR_PKG \
  AIRLOCK_ENGINE \
  AIRLOCK_GID \
  AIRLOCK_HOME \
  AIRLOCK_HOST_CODEX_DIR \
  AIRLOCK_HOST_OPENCODE_CONFIG_DIR \
  AIRLOCK_HOST_OPENCODE_DATA_DIR \
  AIRLOCK_IMAGE \
  AIRLOCK_MOUNT_ENGINE_SOCKET \
  AIRLOCK_MOUNT_STYLE \
  AIRLOCK_MOUNT_OPENCODE \
  AIRLOCK_MOUNT_ROS \
  AIRLOCK_NETWORK \
  AIRLOCK_NPM_REGISTRY \
  AIRLOCK_NPM_VERSION \
  AIRLOCK_NO_CACHE \
  AIRLOCK_OPENCODE_VERSION \
  AIRLOCK_PROFILE \
  AIRLOCK_PULL \
  AIRLOCK_RESOLVE_LATEST \
  AIRLOCK_RM \
  AIRLOCK_SYSTEM_CLEAN_IMAGE \
  AIRLOCK_SYSTEM_REBUILD \
  AIRLOCK_TIMING \
  AIRLOCK_TTY \
  AIRLOCK_UID \
  AIRLOCK_USERNS \
  AIRLOCK_YOLO \
  AIRLOCK_ZSHRC \
  CONTAINER_HOST \
  DOCKER_HOST

mkdir -p "$HOME/.airlock/config" "$HOME/.airlock/image"
printf '%s\n' "# test" >"$HOME/.airlock/config/zshrc"
printf '%s\n' "hello" >"$ro_dir/hello.txt"

ok "unit setup"

## WSL prereq checker script exists and is runnable (logic is host-dependent, so don't assert output).
[[ -x stow/airlock/bin/airlock-wsl-prereqs ]] || fail "expected airlock-wsl-prereqs to be executable"
ok "airlock-wsl-prereqs: present"

## airlock-config helper exists and is runnable (used for ~/.airlock/config.toml defaults).
[[ -x stow/airlock/bin/airlock-config ]] || fail "expected airlock-config to be executable"
ok "airlock-config: present"

## airlock dispatcher exists and can delegate to yolo/build in dry-run mode.
[[ -x stow/airlock/bin/airlock ]] || fail "expected airlock dispatcher to be executable"
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  stow/airlock/bin/airlock dock -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q '^CMD:' || fail "expected airlock dock to delegate to yolo (dry-run prints CMD:)"
printf '%s\n' 'FROM debian:bookworm-slim' >"$HOME/.airlock/image/agent.Dockerfile"
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  stow/airlock/bin/airlock build
)"
printf '%s\n' "$out" | grep -q '^CMD:' || fail "expected airlock build to delegate to airlock-build (dry-run prints CMD:)"
ok "airlock dispatcher: ok"

## config.toml defaults + profiles (requires python3 + tomllib/tomli)
if command -v python3 >/dev/null 2>&1 && python3 - >/dev/null 2>&1 <<'PY'
try:
    import tomllib  # noqa: F401
except ModuleNotFoundError:
    import tomli  # noqa: F401
PY
then
  cfg_toml="$tmp/airlock-config.toml"
  cat >"$cfg_toml" <<TOML
[airlock]
engine = "podman"
image = "airlock-agent:cfg"
network = "host"
mount_engine_socket = true
add_dirs = ["$rw_dir"]
mount_ros = ["$ro_dir"]
publish_ports = ["1455:1455"]

  [profiles.dock]
  network = "bridge"
  mount_engine_socket = false
TOML

  fakebin_cfg="$tmp/fakebin-cfg"
  mkdir -p "$fakebin_cfg"
  cat >"$fakebin_cfg/podman" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fakebin_cfg/podman"

  cfg_out="$(
    AIRLOCK_CONFIG_TOML="$cfg_toml" \
    stow/airlock/bin/airlock-config --profile dock
  )"
  printf '%s\n' "$cfg_out" | grep -q -- 'AIRLOCK_MOUNT_ENGINE_SOCKET=0' || \
    fail "expected [profiles.dock] mount_engine_socket=false to set AIRLOCK_MOUNT_ENGINE_SOCKET=0"

  cfg_toml_mount_style="$tmp/airlock-config-mount-style.toml"
  cat >"$cfg_toml_mount_style" <<'TOML'
[airlock]
mount_style = "host-prefix"
TOML
  cfg_out="$(
    AIRLOCK_CONFIG_TOML="$cfg_toml_mount_style" \
    stow/airlock/bin/airlock-config --profile dock
  )"
  printf '%s\n' "$cfg_out" | grep -q -- 'AIRLOCK_MOUNT_STYLE=host-prefix' || \
    fail "expected config.toml mount_style=host-prefix to set AIRLOCK_MOUNT_STYLE=host-prefix"
  ok "config.toml mount_style: ok"

  out="$(
    PATH="$fakebin_cfg:$PATH" \
    AIRLOCK_CONFIG_TOML="$cfg_toml" \
    AIRLOCK_DRY_RUN=1 \
    stow/airlock/bin/airlock dock -- bash -lc 'echo ok'
  )"
  printf '%s\n' "$out" | grep -q 'Image:      airlock-agent:cfg' || fail "expected config.toml to set AIRLOCK_IMAGE"
  if printf '%s\n' "$out" | grep -q -- '--network host'; then
    fail "expected [profiles.dock] network=bridge override to disable host networking"
  fi
  printf '%s\n' "$out" | grep -q -- "-v $ro_dir:$ro_dir:ro" || fail "expected config.toml mount_ros to bind-mount ro"
  printf '%s\n' "$out" | grep -q -- "-v $rw_dir:$rw_dir:rw" || fail "expected config.toml add_dirs to bind-mount rw"
  printf '%s\n' "$out" | grep -q -- "-p 1455:1455" || fail "expected config.toml publish_ports to publish ports"
  ok "config.toml profile dock: ok"

  out="$(
    PATH="$fakebin_cfg:$PATH" \
    AIRLOCK_CONFIG_TOML="$cfg_toml" \
    AIRLOCK_DRY_RUN=1 \
    AIRLOCK_NETWORK=host \
    stow/airlock/bin/airlock dock -- bash -lc 'echo ok'
  )"
  printf '%s\n' "$out" | grep -q -- '--network host' || fail "expected env vars to override config.toml"
  ok "config.toml precedence env>config: ok"

  cfg_out="$(
    AIRLOCK_CONFIG_TOML="$cfg_toml" \
    stow/airlock/bin/airlock-config --profile yolo
  )"
  printf '%s\n' "$cfg_out" | grep -q -- 'AIRLOCK_MOUNT_ENGINE_SOCKET=1' || \
    fail "expected base mount_engine_socket=true to set AIRLOCK_MOUNT_ENGINE_SOCKET=1 for profile yolo"

  out="$(
    PATH="$fakebin_cfg:$PATH" \
    AIRLOCK_CONFIG_TOML="$cfg_toml" \
    AIRLOCK_DRY_RUN=1 \
    stow/airlock/bin/airlock yolo -- bash -lc 'echo ok'
  )"
  printf '%s\n' "$out" | grep -q -- '--network host' || fail "expected base config.toml network=host to apply"
  ok "config.toml profile yolo: ok"
else
  echo "WARN: python3 tomllib/tomli not available; skipping config.toml unit tests."
fi

## agent image: editor support for $EDITOR
grep -q -- 'ARG EDITOR_PKG=vim-tiny' stow/airlock/.airlock/image/agent.Dockerfile || \
  fail "expected agent.Dockerfile to default EDITOR_PKG to vim-tiny"
expected_editor_expr="\${EDITOR_PKG}"
grep -Fq -- "$expected_editor_expr" stow/airlock/.airlock/image/agent.Dockerfile || \
  fail "expected agent.Dockerfile to install editor from EDITOR_PKG build arg"
grep -q -- 'EDITOR=vi' stow/airlock/.airlock/image/agent.Dockerfile || \
  fail "expected agent.Dockerfile to set default EDITOR=vi"
grep -q -- 'VISUAL=vi' stow/airlock/.airlock/image/agent.Dockerfile || \
  fail "expected agent.Dockerfile to set default VISUAL=vi"
ok "agent image editor defaults: ok"

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
printf '%s\n' "$out" | grep -q -- "-v $HOME/.config/opencode:/home/airlock/.config/opencode:rw" || \
  fail "expected yolo to mount host ~/.config/opencode by default"
printf '%s\n' "$out" | grep -q -- "-v $HOME/.local/share/opencode:/home/airlock/.local/share/opencode:rw" || \
  fail "expected yolo to mount host ~/.local/share/opencode by default"
if printf '%s\n' "$out" | grep -q -- '/home/airlock/.codex/config.toml:ro'; then
  fail "expected yolo to NOT mount codex config.toml by default"
fi
ok "yolo dry-run defaults: ok"

## yolo: passes AIRLOCK_PODMAN_STORAGE_DRIVER through to the container
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_PODMAN_STORAGE_DRIVER=vfs \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q -- "-e AIRLOCK_PODMAN_STORAGE_DRIVER=vfs" || \
  fail "expected yolo to forward AIRLOCK_PODMAN_STORAGE_DRIVER"
ok "yolo nested podman storage driver: ok"

## yolo: OpenCode mounts are opt-out
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_MOUNT_OPENCODE=0 \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
if printf '%s\n' "$out" | grep -q -- "/home/airlock/.config/opencode"; then
  fail "expected yolo to omit OpenCode mounts when AIRLOCK_MOUNT_OPENCODE=0"
fi
if printf '%s\n' "$out" | grep -q -- "/home/airlock/.local/share/opencode"; then
  fail "expected yolo to omit OpenCode mounts when AIRLOCK_MOUNT_OPENCODE=0"
fi
ok "yolo OpenCode mounts opt-out: ok"

## yolo: publish ports
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  stow/airlock/bin/yolo --publish 1455:1455 -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q -- "-p 1455:1455" || fail "expected yolo --publish to add -p"
ok "yolo publish ports: ok"

## yolo: host networking opt-in
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_NETWORK=host \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q -- '--network host' || fail "expected yolo to include --network host"
ok "yolo host networking opt-in: ok"

## yolo: podman does not default to userns=keep-id (rootless/userns is unsupported)
fakebin_podman="$tmp/fakebin-podman"
mkdir -p "$fakebin_podman"
cat >"$fakebin_podman/podman" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fakebin_podman/podman"

out="$(
  PATH="$fakebin_podman:$PATH" \
  AIRLOCK_ENGINE=podman \
  AIRLOCK_DRY_RUN=1 \
  stow/airlock/bin/yolo -- bash -lc 'echo ok'
)"
if printf '%s\n' "$out" | grep -q -- '--userns=keep-id'; then
  fail "expected yolo to NOT default podman userns to keep-id"
fi
ok "yolo podman keep-id default: ok (absent)"

## yolo: --dind runs privileged
out="$(
  PATH="$fakebin_podman:$PATH" \
  AIRLOCK_ENGINE=podman \
  AIRLOCK_DRY_RUN=1 \
  stow/airlock/bin/yolo --dind -- bash -lc 'echo ok'
)"
printf '%s\n' "$out" | grep -q -- '--privileged' || fail "expected yolo --dind to include --privileged"
printf '%s\n' "$out" | grep -q -- '-e AIRLOCK_DIND=1' || fail "expected yolo --dind to set AIRLOCK_DIND=1"
printf '%s\n' "$out" | grep -q -- '-e AIRLOCK_DIND_STORAGE_DRIVER=vfs' || \
  fail "expected yolo --dind to default AIRLOCK_DIND_STORAGE_DRIVER to vfs"
ok "yolo dind: ok"

## yolo: docker does not use --user by default (entrypoint maps uid/gid)
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
if printf '%s\n' "$out" | grep -q -- "--user $(id -u):$(id -g)"; then
  fail "expected yolo to NOT include --user uid:gid for docker by default"
fi
ok "yolo docker user default: ok (absent)"

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

## yolo: extra dirs (ro + rw mounts); forwards rw mounts to codex --add-dir
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  stow/airlock/bin/yolo --mount-ro "$ro_dir" --add-dir "$rw_dir" -- codex --profile yolo --help
)"
printf '%s\n' "$out" | grep -q -- "-v $ro_dir:$ro_dir:ro" || fail "expected yolo --mount-ro to bind-mount ro"
printf '%s\n' "$out" | grep -q -- "-v $rw_dir:$rw_dir:rw" || fail "expected yolo --add-dir to bind-mount rw"
printf '%s\n' "$out" | grep -q -- " codex " || fail "expected yolo to run codex"
printf '%s\n' "$out" | grep -q -- "--add-dir $rw_dir" || fail "expected yolo to inject codex --add-dir for rw mount"
if printf '%s\n' "$out" | grep -q -- "--add-dir $ro_dir"; then
  fail "expected yolo to NOT inject codex --add-dir for ro mount"
fi
ok "yolo extra dirs + codex injection: ok"

## yolo: host-prefixed mounts (mount everything under /host<abs>)
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  stow/airlock/bin/yolo --mount-style=host-prefix --mount-ro "$ro_dir" --add-dir "$rw_dir" -- codex --profile yolo --help
)"
printf '%s\n' "$out" | grep -q -- "-v $ro_dir:/host$ro_dir:ro" || fail "expected yolo --mount-style=host-prefix to bind-mount ro under /host"
printf '%s\n' "$out" | grep -q -- "-v $rw_dir:/host$rw_dir:rw" || fail "expected yolo --mount-style=host-prefix to bind-mount rw under /host"
printf '%s\n' "$out" | grep -q -- "--add-dir /host$rw_dir" || fail "expected yolo --mount-style=host-prefix to inject codex --add-dir under /host for rw mount"
if printf '%s\n' "$out" | grep -q -- "--add-dir /host$ro_dir"; then
  fail "expected yolo --mount-style=host-prefix to NOT inject codex --add-dir for ro mount"
fi
ok "yolo --mount-style=host-prefix: ok"

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

## yolo: opencode fails fast if host ~/.local/share/opencode/auth.json is unreadable
# Note: this is only meaningful when running as a non-root user; root can read 000 files.
if [[ "$(id -u)" -eq 0 ]]; then
  ok "yolo unreadable host OpenCode auth guard: n/a (running as root)"
else
  mkdir -p "$HOME/.local/share/opencode"
  printf '%s\n' "{}" >"$HOME/.local/share/opencode/auth.json"
  chmod 000 "$HOME/.local/share/opencode/auth.json"

  set +e
  out="$(
    AIRLOCK_ENGINE=true \
    AIRLOCK_DRY_RUN=1 \
    stow/airlock/bin/yolo -- opencode --help 2>&1
  )"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "expected yolo to exit non-zero when host OpenCode auth.json is unreadable"
  printf '%s\n' "$out" | grep -q 'ERROR: host OpenCode auth not readable' || \
    fail "expected yolo to print an actionable error for unreadable host OpenCode auth"

  chmod 600 "$HOME/.local/share/opencode/auth.json"
  ok "yolo unreadable host OpenCode auth guard: ok"
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

  printf '%s\n' "$out" | grep -q -- "-v $workrepo:$workrepo:rw" || fail "expected yolo to mount git repo root at canonical path"
  printf '%s\n' "$out" | grep -q -- "-w $workrepo/sub/dir" || fail "expected yolo to set canonical workdir to subdir within mounted repo"
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
  AIRLOCK_OPENCODE_VERSION=0.0.0 \
  AIRLOCK_NPM_VERSION=9.9.9 \
  AIRLOCK_EDITOR_PKG=vim-nox \
  stow/airlock/bin/airlock-build
)"
printf '%s\n' "$out" | grep -q '^CMD:' || fail "expected airlock-build dry-run to print CMD:"
printf '%s\n' "$out" | grep -q -- ' build ' || fail "expected airlock-build to use engine build"
printf '%s\n' "$out" | grep -q -- 'BASE_IMAGE=example/base:latest' || fail "expected BASE_IMAGE build-arg"
printf '%s\n' "$out" | grep -q -- 'CODEX_VERSION=0.0.0' || fail "expected CODEX_VERSION build-arg"
printf '%s\n' "$out" | grep -q -- 'OPENCODE_VERSION=0.0.0' || fail "expected OPENCODE_VERSION build-arg"
printf '%s\n' "$out" | grep -q -- 'NPM_VERSION=9.9.9' || fail "expected NPM_VERSION build-arg"
printf '%s\n' "$out" | grep -q -- 'EDITOR_PKG=vim-nox' || fail "expected EDITOR_PKG build-arg"
ok "airlock-build dry-run: ok"

## airlock-build: --no-cache knob
out="$(
  AIRLOCK_ENGINE=true \
  AIRLOCK_DRY_RUN=1 \
  AIRLOCK_NO_CACHE=1 \
  AIRLOCK_IMAGE=airlock-agent:test \
  AIRLOCK_BASE_IMAGE=example/base:latest \
  AIRLOCK_CODEX_VERSION=0.0.0 \
  stow/airlock/bin/airlock-build
)"
printf '%s\n' "$out" | grep -q -- '--no-cache' || fail "expected airlock-build to pass --no-cache when AIRLOCK_NO_CACHE=1"
ok "airlock-build no-cache: ok"

## airlock-build: config.toml defaults + profile overrides (requires python3 + tomllib/tomli)
if command -v python3 >/dev/null 2>&1 && python3 - >/dev/null 2>&1 <<'PY'
try:
    import tomllib  # noqa: F401
except ModuleNotFoundError:
    import tomli  # noqa: F401
PY
then
  fakebin_cfg_build="$tmp/fakebin-cfg-build"
  mkdir -p "$fakebin_cfg_build"
  cat >"$fakebin_cfg_build/podman" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fakebin_cfg_build/podman"

  cfg_build="$tmp/airlock-build-config.toml"
  cat >"$cfg_build" <<'TOML'
[airlock]
engine = "podman"
image = "airlock-agent:cfgbuild"

[build]
base_image = "example/base:cfg"
codex_version = "1.2.3"
opencode_version = "4.5.6"
npm_version = "9.9.9"
editor_pkg = "vim-nox"
pull = false

[profiles.build]
npm_version = "8.8.8"
TOML

  out="$(
    PATH="$fakebin_cfg_build:$PATH" \
    AIRLOCK_CONFIG_TOML="$cfg_build" \
    AIRLOCK_DRY_RUN=1 \
    stow/airlock/bin/airlock build
  )"
  printf '%s\n' "$out" | grep -q 'Image:      airlock-agent:cfgbuild' || fail "expected config.toml to set AIRLOCK_IMAGE for build"
  printf '%s\n' "$out" | grep -q -- 'BASE_IMAGE=example/base:cfg' || fail "expected config.toml to set build.base_image"
  printf '%s\n' "$out" | grep -q -- 'CODEX_VERSION=1.2.3' || fail "expected config.toml to set build.codex_version"
  printf '%s\n' "$out" | grep -q -- 'OPENCODE_VERSION=4.5.6' || fail "expected config.toml to set build.opencode_version"
  printf '%s\n' "$out" | grep -q -- 'NPM_VERSION=8.8.8' || fail "expected [profiles.build] to override build.npm_version"
  printf '%s\n' "$out" | grep -q -- 'EDITOR_PKG=vim-nox' || fail "expected config.toml to set build.editor_pkg"
  printf '%s\n' "$out" | grep -q -- '--pull-never' || fail "expected build.pull=false to disable pulls"
  ok "airlock-build config.toml defaults + profile: ok"

  out="$(
    PATH="$fakebin_cfg_build:$PATH" \
    AIRLOCK_CONFIG_TOML="$cfg_build" \
    AIRLOCK_DRY_RUN=1 \
    AIRLOCK_NPM_VERSION=7.7.7 \
    stow/airlock/bin/airlock build
  )"
  printf '%s\n' "$out" | grep -q -- 'NPM_VERSION=7.7.7' || fail "expected env AIRLOCK_NPM_VERSION to override config.toml"
  ok "airlock-build precedence env>config: ok"
else
  echo "WARN: python3 tomllib/tomli not available; skipping airlock-build config.toml unit tests."
fi

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

## scripts/install.sh + scripts/uninstall.sh: symlink install mode (no stow)
install_home="$tmp/install-home"
mkdir -p "$install_home"

HOME="$install_home" AIRLOCK_INSTALL_MODE=symlink "$REPO_ROOT/scripts/install.sh"

[[ -L "$install_home/bin/yolo" ]] || fail "expected symlink install to create ~/bin/yolo"
[[ -L "$install_home/bin/airlock" ]] || fail "expected symlink install to create ~/bin/airlock"
[[ -L "$install_home/bin/airlock-config" ]] || fail "expected symlink install to create ~/bin/airlock-config"
[[ -L "$install_home/bin/airlock-build" ]] || fail "expected symlink install to create ~/bin/airlock-build"
[[ -L "$install_home/bin/airlock-doctor" ]] || fail "expected symlink install to create ~/bin/airlock-doctor"
[[ -L "$install_home/bin/airlock-wsl-prereqs" ]] || fail "expected symlink install to create ~/bin/airlock-wsl-prereqs"
[[ -L "$install_home/.airlock/config" ]] || fail "expected symlink install to create ~/.airlock/config symlink"
[[ -L "$install_home/.airlock/image" ]] || fail "expected symlink install to create ~/.airlock/image symlink"

real_yolo="$(readlink -f "$install_home/bin/yolo")"
real_yolo_src="$(readlink -f "$REPO_ROOT/stow/airlock/bin/yolo")"
[[ "$real_yolo" == "$real_yolo_src" ]] || fail "expected ~/bin/yolo to link to repo yolo script"

HOME="$install_home" AIRLOCK_INSTALL_MODE=symlink "$REPO_ROOT/scripts/uninstall.sh"

[[ ! -e "$install_home/bin/yolo" ]] || fail "expected symlink uninstall to remove ~/bin/yolo"
[[ ! -e "$install_home/bin/airlock" ]] || fail "expected symlink uninstall to remove ~/bin/airlock"
[[ ! -e "$install_home/bin/airlock-config" ]] || fail "expected symlink uninstall to remove ~/bin/airlock-config"
[[ ! -e "$install_home/bin/airlock-build" ]] || fail "expected symlink uninstall to remove ~/bin/airlock-build"
[[ ! -e "$install_home/bin/airlock-doctor" ]] || fail "expected symlink uninstall to remove ~/bin/airlock-doctor"
[[ ! -e "$install_home/bin/airlock-wsl-prereqs" ]] || fail "expected symlink uninstall to remove ~/bin/airlock-wsl-prereqs"
[[ ! -e "$install_home/.airlock/config" ]] || fail "expected symlink uninstall to remove ~/.airlock/config"
[[ ! -e "$install_home/.airlock/image" ]] || fail "expected symlink uninstall to remove ~/.airlock/image"

ok "symlink install/uninstall: ok"

## stow install/uninstall (idempotence + symlinks)
if command -v stow >/dev/null 2>&1; then
  stow_home="$tmp/stow-home"
  mkdir -p "$stow_home/.airlock" "$stow_home/bin"

  stow -d "$REPO_ROOT/stow" -t "$stow_home" airlock
  [[ -d "$stow_home/.airlock" && ! -L "$stow_home/.airlock" ]] || fail "expected .airlock to be a real directory"
  [[ -L "$stow_home/.airlock/config" ]] || fail "expected stowed config to be symlinked"
  [[ -L "$stow_home/.airlock/image" ]] || fail "expected stowed image to be symlinked"
  [[ -L "$stow_home/bin/yolo" ]] || fail "expected stowed yolo to be a symlink"
  [[ -L "$stow_home/bin/airlock" ]] || fail "expected stowed airlock dispatcher to be a symlink"
  [[ -L "$stow_home/bin/airlock-config" ]] || fail "expected stowed airlock-config to be a symlink"
  [[ -L "$stow_home/bin/airlock-wsl-prereqs" ]] || fail "expected stowed airlock-wsl-prereqs to be a symlink"
  [[ -e "$stow_home/.airlock/config/zshrc" ]] || fail "expected zshrc to exist under stowed config"

  stow -d "$REPO_ROOT/stow" -t "$stow_home" airlock
  ok "stow idempotence: ok"

  stow -D -d "$REPO_ROOT/stow" -t "$stow_home" airlock
  [[ -d "$stow_home/bin" ]] || fail "expected bin directory to remain after uninstall"
  [[ -d "$stow_home/.airlock" ]] || fail "expected .airlock directory to remain after uninstall"
  [[ ! -e "$stow_home/bin/yolo" ]] || fail "expected yolo removed after uninstall"
  [[ ! -e "$stow_home/bin/airlock" ]] || fail "expected airlock removed after uninstall"
  [[ ! -e "$stow_home/bin/airlock-config" ]] || fail "expected airlock-config removed after uninstall"
  [[ ! -e "$stow_home/bin/airlock-wsl-prereqs" ]] || fail "expected airlock-wsl-prereqs removed after uninstall"
  [[ ! -e "$stow_home/.airlock/config" ]] || fail "expected config symlink removed after uninstall"
  [[ ! -e "$stow_home/.airlock/image" ]] || fail "expected image symlink removed after uninstall"
  ok "stow uninstall: ok"
else
  echo "WARN: stow not found; skipping stow unit tests."
fi

ok "unit tests: complete"
