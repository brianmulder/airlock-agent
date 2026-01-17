# Airlock Runbook

This runbook is a step-by-step tutorial for installing, using, and dogfooding Airlock.

## 1) Prerequisites

- A Linux host with `sudo`.
- A container engine (default: Podman).
- GNU Stow.

Supported engines (set `AIRLOCK_ENGINE` to select):

- `docker` (Docker Desktop)
- `nerdctl` (commonly used with Rancher Desktop / containerd)
- `podman` (Podman / Podman Desktop)

If `podman run` feels “stuck” before the container prints anything, enable coarse timing to confirm where
the delay is:

```bash
AIRLOCK_TIMING=1 AIRLOCK_ENGINE=podman yolo -- bash -lc 'true'
```

## 2) Prepare a Context Directory

Airlock does not mount any “extra” directories by default. If you want to provide read-only inputs or a
separate writable outbox, mount them explicitly:

- Read-only: `yolo --mount-ro /path/to/inputs -- ...` (mounted at `/host<abs>` inside the container)
- Read-write: `yolo --add-dir /path/to/outbox -- ...` (mounted at `/host<abs>` and forwarded to Codex as `--add-dir`)

## 3) Install Airlock via Stow

Required:

```bash
mkdir -p ~/.airlock ~/bin
sudo apt-get update && sudo apt-get install -y stow
stow -d ~/code/github.com/brianmulder/airlock/stow -t ~ airlock
hash -r
```

Alternative (recommended):

```bash
./scripts/install.sh
```

You should now have:

- `~/bin/yolo`
- `~/bin/airlock-build`
- `~/bin/airlock-doctor`
- `~/.airlock/policy/*`
- `~/.airlock/image/*`

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
yolo
```

Note: the workspace is mounted at a canonical `/host<host-path>` so Codex and git tooling don’t conflate
sessions across different repos.

Example (optional engine selection):

```bash
AIRLOCK_ENGINE=nerdctl yolo
```

Inside the container:

Required:

```bash
codex
```

Recommended:

```bash
yolo -- codex
```

Auth persistence note:
- By default, `yolo` mounts your host `~/.codex/` into the container (rw), so your login/config “just works”.
- If you prefer Airlock-managed state under `~/.airlock/codex-state/` (with policy overrides), opt in:

```bash
AIRLOCK_CODEX_HOME_MODE=airlock yolo -- codex
```

- To reuse an existing host login with Airlock-managed state:

```bash
mkdir -p ~/.airlock/codex-state
cp ~/.codex/auth.json ~/.airlock/codex-state/auth.json
chmod 600 ~/.airlock/codex-state/auth.json
```

## 7) Smoke Test (No Agent)

This validates mounts and basic mechanics without running `codex`:

```bash
ro_dir="$(mktemp -d)"; rw_dir="$(mktemp -d)"
echo "hello" >"$ro_dir/hello.txt"
yolo --mount-ro "$ro_dir" --add-dir "$rw_dir" -- bash -lc \
  'set -e; test -f "/host'"$ro_dir"'/hello.txt"; touch "/host'"$rw_dir"'/ok"; ! touch "/host'"$ro_dir"'/nope"'
```

To run the full system smoke test script (stow → build → yolo), allow pulls if needed:

```bash
AIRLOCK_PULL=1 AIRLOCK_ENGINE=podman ./scripts/test-system.sh
```

## 8) Review + Promote Outputs

- Prefer a dedicated writable outbox on the host and mount it with `--add-dir`.
- Review on the host (Neovim, git diff) before copying anything into your repo.

Example:

```bash
mkdir -p ~/tmp/airlock-outbox
yolo --add-dir ~/tmp/airlock-outbox -- codex
# ...review ~/tmp/airlock-outbox/* on the host, then copy/commit as desired...
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
