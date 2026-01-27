# Getting Started

This guide is a step-by-step tutorial for installing and using Airlock.

See also `docs/decisions.md` and `docs/threat-model.md`.
For day-to-day operational safety notes, see `docs/dos-and-donts.md`.

## 1) Prerequisites

- A Linux host with `sudo`.
- A **rootful** container engine reachable from your user (recommended: Docker).
- Optional but recommended: GNU Stow (for installing Airlock into `~/bin` and `~/.airlock`).

Supported engines (set `AIRLOCK_ENGINE` to select):

- `docker` (Docker Desktop)
- `nerdctl` (commonly used with Rancher Desktop / containerd)
- `podman` (Podman / Podman Desktop)

Note: Airlock does **not** support rootless engines at this time (rootless Podman commonly fails on
UID/GID mappings and/or `/dev/net/tun` networking). Use a rootful engine.

WSL note: if you’re on WSL2, getting rootful Podman exposed to your user can be surprisingly fiddly.
See `docs/wsl-rootful-engines.md` for a worked setup (systemd, sockets, tmpfiles overrides).

If `podman run` feels “stuck” before the container prints anything, enable coarse timing to confirm where
the delay is:

```bash
AIRLOCK_TIMING=1 AIRLOCK_ENGINE=podman yolo -- bash -lc 'true'
```

## 2) Mount Extra Directories (RO/RW)

Airlock does not mount arbitrary host directories by default.

`yolo` mounts your workspace plus tool state/cache mounts (so auth and caches persist). If you want additional
host inputs or extra writable directories, add mounts explicitly when running `yolo`:

- Read-only: `yolo --mount-ro /path/to/inputs -- ...` (mounted at `<abs>` inside the container)
- Read-write: `yolo --add-dir /path/to/writes -- ...` (mounted at `<abs>` and forwarded to Codex as `--add-dir <abs>`)

Tip: for stricter separation (all host mounts under `/host<abs>`), use `yolo --mount-style=host-prefix` or set
`AIRLOCK_MOUNT_STYLE=host-prefix`.

## 3) Install Airlock

Option A — Stow (recommended):

```bash
mkdir -p ~/.airlock ~/bin
sudo apt-get update && sudo apt-get install -y stow
stow -d ~/code/github.com/brianmulder/airlock/stow -t ~ airlock
hash -r
```

Or:

```bash
./scripts/install.sh
```

Tip: `./scripts/install.sh` uses Stow when available; otherwise it installs via symlinks. You can force a
mode with `AIRLOCK_INSTALL_MODE=stow|symlink`.

Option B — Without stow (symlink install):

```bash
mkdir -p ~/.airlock ~/bin

# Adjust this path to where you cloned the repo
AIRLOCK_REPO=~/code/github.com/brianmulder/airlock

ln -s "$AIRLOCK_REPO/stow/airlock/bin/yolo" ~/bin/yolo
ln -s "$AIRLOCK_REPO/stow/airlock/bin/airlock" ~/bin/airlock
ln -s "$AIRLOCK_REPO/stow/airlock/bin/airlock-config" ~/bin/airlock-config
ln -s "$AIRLOCK_REPO/stow/airlock/bin/airlock-build" ~/bin/airlock-build
ln -s "$AIRLOCK_REPO/stow/airlock/bin/airlock-doctor" ~/bin/airlock-doctor
ln -s "$AIRLOCK_REPO/stow/airlock/bin/airlock-wsl-prereqs" ~/bin/airlock-wsl-prereqs

ln -s "$AIRLOCK_REPO/stow/airlock/.airlock/config" ~/.airlock/config
ln -s "$AIRLOCK_REPO/stow/airlock/.airlock/image" ~/.airlock/image
```

Option C — Without stow (copy install, no symlinks):

```bash
mkdir -p ~/.airlock ~/bin

# Adjust this path to where you cloned the repo
AIRLOCK_REPO=~/code/github.com/brianmulder/airlock

cp -a "$AIRLOCK_REPO/stow/airlock/bin/." ~/bin/
cp -a "$AIRLOCK_REPO/stow/airlock/.airlock/config" ~/.airlock/
cp -a "$AIRLOCK_REPO/stow/airlock/.airlock/image" ~/.airlock/
```

You should now have:

- `~/bin/yolo`
- `~/bin/airlock`
- `~/bin/airlock-config`
- `~/bin/airlock-build`
- `~/bin/airlock-doctor`
- `~/bin/airlock-wsl-prereqs`
- `~/.airlock/config/*`
- `~/.airlock/image/*`

Notes:

- `~/.airlock/config/zshrc` is a pinned shell config that `yolo` mounts read-only into the container as
  `/home/airlock/.zshrc`. It keeps the prompt stable and sets `PATH` so project-local `node_modules/.bin`
  is available. Override with `AIRLOCK_ZSHRC=/path/to/zshrc`.
- `~/.airlock/image/*` is the local build context for `airlock-build` (Dockerfile, entrypoint, wrappers).
- Optional: set defaults via `~/.airlock/config.toml` (or override the path with `AIRLOCK_CONFIG_TOML=...`).
  See `docs/configuration.md`.

## 4) Build the Agent Image

Required:

```bash
airlock-build
```

Default base image: `mcr.microsoft.com/devcontainers/javascript-node:20-bookworm`.

Examples (optional):

```bash
AIRLOCK_ENGINE=podman airlock-build
AIRLOCK_BUILD_ISOLATION=oci AIRLOCK_ENGINE=podman airlock-build
AIRLOCK_BASE_IMAGE=mcr.microsoft.com/devcontainers/typescript-node:20-bookworm airlock-build
AIRLOCK_CODEX_VERSION=0.84.0 airlock-build
AIRLOCK_OPENCODE_VERSION=<ver> airlock-build
AIRLOCK_EDITOR_PKG=vim-nox airlock-build
```

Update tip:

- To pick up new Codex/OpenCode releases, rerun `airlock-build` (the image is shared across repos).
- If your engine still uses a cached layer and you keep seeing upgrade notices, force a rebuild with:

```bash
AIRLOCK_NO_CACHE=1 airlock-build
```

## 5) Validate the Environment

Required:

```bash
airlock-doctor
```

Fix any warnings before proceeding (most issues are mount paths or engine connectivity).

## 6) Daily Use

From a project repo on a local filesystem:

Required:

```bash
cd ~/code/your-project
airlock dock
```

Note: the workspace is mounted at its host absolute path (`<host-path>`) so Codex and git tooling don’t conflate
sessions across different repos. For stricter separation, use `AIRLOCK_MOUNT_STYLE=host-prefix`.

Notes:

- `airlock dock` is the recommended entrypoint (safer defaults: engine socket passthrough disabled).
- `yolo` is still available as the underlying implementation.

Tip: if you run `yolo` again from the same directory while the container is still running, it will attach.
Use `yolo --new` to start a second container.

Example (optional engine selection):

```bash
AIRLOCK_ENGINE=nerdctl airlock dock
```

### Containers from inside `yolo` (optional)

By default, `yolo` will try to mount the host engine socket so you can run container builds from inside the
agent container. `airlock dock` disables this by default; use `airlock yolo` (or `yolo --engine-socket`) to
force-enable socket passthrough when desired.

If you prefer not to mount the host engine socket, you can opt into Docker-in-Docker:

```bash
yolo --dind -- bash -lc 'docker version; docker info'
```

See `docs/docker-in-docker.md` for details and limitations.

Inside the container:

Required:

```bash
codex
```

Or:

```bash
opencode
```

Recommended:

```bash
yolo -- codex
```

Or:

```bash
yolo -- opencode
```

Auth persistence note:

- By default, `yolo` mounts your host `~/.codex/` into the container (rw), so your login/config “just works”.
- By default, `yolo` mounts your host OpenCode state (`~/.config/opencode/` and `~/.local/share/opencode/`) into the
  container (rw), so your auth/config persists across runs.
- If OpenCode login redirects to `http://localhost:1455/...` (OAuth callback), publish that port:

```bash
yolo --publish 1455:1455 -- opencode auth login
```

## 7) Smoke Test (No Agent)

This validates mounts and basic mechanics without running `codex`:

```bash
ro_dir="$(mktemp -d)"; rw_dir="$(mktemp -d)"
echo "hello" >"$ro_dir/hello.txt"
yolo --mount-ro "$ro_dir" --add-dir "$rw_dir" -- bash -lc \
  "set -e; test -f '$ro_dir/hello.txt'; touch '$rw_dir/ok'; ! touch '$ro_dir/nope'"
```

To run the full system smoke test script (stow → build → yolo), allow pulls if needed:

```bash
AIRLOCK_PULL=1 AIRLOCK_ENGINE=docker ./scripts/test-system.sh
```

Tip: by default `./scripts/test-system.sh` will reuse an existing `airlock-agent:local` image if present.
Force a rebuild with:

```bash
AIRLOCK_SYSTEM_REBUILD=1 ./scripts/test-system.sh
```

## 8) Review + Promote Outputs

- Prefer putting agent outputs in a host directory mounted via `--add-dir`.
- Review on the host (Neovim, git diff) before copying anything into your repo.

Example:

```bash
mkdir -p ~/tmp/airlock-writes
yolo --add-dir ~/tmp/airlock-writes -- codex
# ...review ~/tmp/airlock-writes/* on the host, then copy/commit as desired...
```

## 9) Dogfooding from Dotfiles (Stow)

### Option A — Submodule (recommended)

```bash
cd ~/code/github.com/brianmulder/dotfiles
mkdir -p vendor

git submodule add https://github.com/brianmulder/airlock vendor/airlock
stow -d vendor/airlock/stow -t ~ airlock
```

### Option B — Vendor the stow package

Copy `stow/airlock/` into your dotfiles repo and:

```bash
stow -t ~ airlock
```

## 10) Troubleshooting

- If `airlock-build` fails, confirm your selected engine is working (try: `${AIRLOCK_ENGINE:-podman} info`).
- If a mount is missing, confirm the host directory exists and your `yolo --mount-ro/--add-dir` flags are correct.
- If you need to build/run containers from inside `yolo`, ensure your host engine socket is available
  (run `airlock-doctor` for the suggested setup).
