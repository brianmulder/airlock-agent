# Airlock Runbook

This runbook is a step-by-step tutorial for installing, using, and dogfooding Airlock.

## 1) Prerequisites

- Windows 11 with WSL2.
- A container engine (default: Podman) with WSL integration enabled.
- Dropbox installed on Windows with a dedicated context subfolder (example: `Dropbox\\fred`).
- A WSL distro with `sudo` access.

Supported engines (set `AIRLOCK_ENGINE` to select):

- `docker` (Docker Desktop)
- `nerdctl` (commonly used with Rancher Desktop / containerd)
- `podman` (Podman / Podman Desktop)

Podman note (WSL): if you see warnings about missing `/run/user/<uid>/bus`, install `dbus-user-session`
and enable lingering (`sudo loginctl enable-linger $(id -u)`). Airlock also defaults Podman builds to
`--isolation=chroot` to avoid common WSL/systemd runtime issues.

If `podman run` feels “stuck” before the container prints anything, enable coarse timing to confirm where
the delay is:

```bash
AIRLOCK_TIMING=1 AIRLOCK_ENGINE=podman yolo -- bash -lc 'true'
```

## 2) Harden WSL and Mount Context

Follow `docs/WSL_HARDENING.md` to:

- Disable automatic Windows drive mounts.
- Mount only your context subfolder into WSL (not all of Dropbox).

If you’re not ready to mount Dropbox yet, `yolo` still runs: it will create an empty context directory at
`~/tmp/airlock_context` and mount it read-only as `/context`.

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

Fix any warnings before proceeding (most issues are WSL mount or Docker connectivity).

## 6) Daily Use

From a WSL-native repo (ext4, not `/mnt/c`):

Required:

```bash
cd ~/code/your-project
yolo
```

Note: `/work` is always available as the short alias, but the default container working directory is a canonical
`/host<WSL-path>` so Codex and git tooling don’t conflate sessions across different repos.

If you mounted a Dropbox context folder into WSL, point `yolo` at it:

```bash
export AIRLOCK_CONTEXT_DIR=~/dropbox/fred
yolo
```

Example (optional engine selection):

```bash
AIRLOCK_ENGINE=nerdctl yolo
```

Inside the container:

Required:

```bash
codex
```

Auth persistence note:
- By default, `yolo` mounts your host `~/.codex/` into the container (rw), so your login/config “just works”.
- If you prefer Airlock-managed state under `~/.airlock/codex-state/` (with policy overrides), opt in:

```bash
AIRLOCK_CODEX_HOME_MODE=airlock yolo
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
yolo -- bash -lc 'set -e; touch /work/ok; touch /drafts/ok; ! touch /context/nope'
```

To run the full system smoke test script (stow → build → yolo), allow pulls if needed:

```bash
AIRLOCK_PULL=1 AIRLOCK_ENGINE=podman ./scripts/test-system.sh
```

## 8) Review + Promote Outputs

- Agent artifacts are written to `~/.airlock/outbox/drafts/`.
- Review in WSL (Neovim, git diff).
- Manually copy approved outputs into your repo or Dropbox:

Example:

```bash
cp ~/.airlock/outbox/drafts/thing.patch ~/dropbox/fred/outbox/reviewed/
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

- If `/mnt/c` appears, re-check `/etc/wsl.conf` and run `wsl --shutdown`.
- If `airlock-build` fails, confirm Docker Desktop is running.
- If context is missing, confirm your `/etc/fstab` entry and Dropbox path.
