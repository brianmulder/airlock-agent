# Airlock

> “Good fences make good neighbors.” — Robert Frost, *Mending Wall* (1914)

Airlock is a **Linux-first container harness for AI coding agents** (Codex, OpenCode, etc.).
It runs your agent in an **ephemeral container** and only exposes what you explicitly mount.

**The point is not “read-only safety.”**
Airlock is designed to let an agent **write directly into your repo** while keeping the rest of your host out
of reach.

## What you get

- **Workspace mounted RW** at its host absolute path: `<absolute-host-path>`
  (repo root when inside git, so `.git/` is present)
  - Optional: `AIRLOCK_MOUNT_STYLE=host-prefix` (or `yolo --mount-style=host-prefix`) mounts under `/host<abs>`.
- **Explicit extra mounts**:
  - `--mount-ro <dir>` for read-only inputs
  - `--add-dir <dir>` for extra writable dirs (also forwarded to `codex --add-dir …`)
- **Tool state + caches mounted from the host** (e.g. `~/.codex`, OpenCode state, `~/.airlock/cache`) so
  logins and installs persist across runs
- Works with **Docker / Podman / nerdctl** (rootful engines recommended)

Docs worth reading:

- `docs/getting-started.md`
- `docs/configuration.md`
- `docs/dos-and-donts.md`
- `docs/threat-model.md`

## Quickstart

```bash
# Install (recommended)
./scripts/install.sh

# Build the image
airlock-build

# From inside a project repo:
cd ~/code/your-project

# Dock into the container:
airlock dock

# Or run an agent directly:
airlock dock -- codex
airlock dock -- opencode
```

Mount additional directories explicitly:

```bash
# Read-only inputs
airlock dock --mount-ro ~/tmp/inputs -- codex

# Extra writable directory (also forwarded to `codex --add-dir ...`)
airlock dock --add-dir ~/tmp/airlock-writes -- codex
```

If OpenCode login redirects to `http://localhost:1455/...` (OAuth callback), publish that port:

```bash
airlock dock --publish 1455:1455 -- opencode auth login
```

## Safety model in 30 seconds

Airlock reduces accidental blast radius by making host access **explicit** — but it’s not a magical security
sandbox.

- **It protects you from:** accidental reads/writes to *unmounted* host locations (because they simply aren’t
  there).
- **It does not protect you from:** the agent trashing your working tree. That’s the trade. Use **Git** (and
  branch protection / PR review) as the safety net.
- **Engine socket passthrough is high-trust.**
  If you enable `--engine-socket` (host Docker/Podman socket), the container can ask the host engine to start
  *other* containers with *other* mounts/networking. Only use it when you mean it.

Recommended defaults:

- If you don’t need “containers from inside the container”, run with `--engine-socket=0` (aka
  `--no-engine-socket`).
- If you need containers *without* host socket passthrough, use DinD: `--dind` (privileged; treat as an
  exception).

High-trust convenience (“true yolo”):

- `airlock yolo` (and `yolo`) are reserved for “no apologies” mode (engine socket on, and any other future
  escalations).

## Notes on integrating with what you already have

- This README assumes `airlock dock` / `airlock yolo` are installed. If you installed an older revision,
  reinstall via `./scripts/install.sh` or use `yolo` directly.
- The engine socket flags are: `--engine-socket=0|1` (and `--no-engine-socket` as an alias for
  `--engine-socket=0`).

## Global Agent Notes

Codex also reads `~/.codex/AGENTS.md` for global instructions. A reasonable baseline for Airlock containers:

```markdown
- If `$AIRLOCK_YOLO=1`, you are inside an Airlock container.
- Your filesystem access is defined by explicit bind mounts; ask the user where outputs should go if unsure.
```

Engine selection examples:

```bash
AIRLOCK_ENGINE=podman airlock-build
AIRLOCK_ENGINE=podman airlock dock
AIRLOCK_EDITOR_PKG=vim-nox airlock-build
```

## Note for WSL users

Airlock itself is Linux-first and does not require WSL-specific configuration. If you use it on WSL2, treat
any Windows-mounted paths as “untrusted” by default: keep your workspace and writable mounts on the Linux
filesystem, and mount Windows-backed inputs read-only (e.g., via `airlock dock --mount-ro ...`).

Airlock targets rootful engines. If you want Docker and/or Podman running rootful inside WSL2 (and
accessible from your user), see `docs/wsl-rootful-engines.md`.

## Note for macOS users

macOS support is currently experimental. If you want to try Airlock on macOS, start with Docker Desktop and
Homebrew-provided GNU tools. See `docs/macos.md`.

## Note for Dropbox users

Dropbox is optional. If you want a sync-backed inputs folder, mount it read-only:

```bash
airlock dock --mount-ro ~/path/to/dropbox/inputs -- codex
```

## Repository Layout

- `docs/` – getting started guide and security notes
- `docs/history/` – historical raw transcripts (not maintained)
- `scripts/` – install/uninstall helpers
- `stow/airlock/` – installable package (binaries + templates)
- `docs/decisions.md` – living “why” notes (defaults, tradeoffs, troubleshooting)
- `docs/roadmap.md` and `docs/development-checklist.md` – planning notes (non-authoritative)

## Dogfood From Dotfiles (Stow)

Recommended (submodule):

```bash
cd ~/code/github.com/brianmulder/dotfiles
mkdir -p vendor
git submodule add https://github.com/brianmulder/airlock vendor/airlock
stow -d vendor/airlock/stow -t ~ airlock
```

Alternative (vendor): copy `stow/airlock/` into your dotfiles repo and run `stow -t ~ airlock`.

Optional: set defaults via `~/.airlock/config.toml` (profiles for `dock` / `yolo` / `build`), especially if you
install Airlock via dotfiles. See `docs/configuration.md`.

## Key Design Rules

- By default, writable mounts are your workspace plus tool state/cache mounts (e.g., `~/.codex/`).
- Additional project mounts are explicit (`airlock dock --mount-ro ...` / `airlock dock --add-dir ...`).
- Host networking is opt-in (`AIRLOCK_NETWORK=host`).
- `yolo` mounts the git repo root (or the current directory) at its host absolute path so tools don’t conflate repos.

## Containers From Inside the Container

If you need to build/run containers from inside the Airlock container, you have two options:

- **Host socket passthrough** (high-trust): enable with `airlock yolo` or `--engine-socket`.
- **Docker-in-Docker** (privileged): enable with `--dind` (does not mount the host engine socket).

By default, `airlock dock` disables host engine socket passthrough. If you try to run `docker`/`podman`
without either `--engine-socket` or `--dind`, you’ll typically hit rootless user-namespace failures inside
the container (expected).

```bash
# Engine socket passthrough (high-trust)
airlock yolo -- docker version

# DinD (privileged; no host socket passthrough)
airlock dock --dind -- docker version
```

See `docs/docker-in-docker.md` for details and limitations.

Note: when the host engine is Podman, `docker` talking to the Podman socket is often more reliable than
`podman --remote` because it avoids Podman client/server version skew.

Rootless engines are currently unsupported:

- Airlock targets rootful engines (recommended: Docker). Rootless Podman commonly fails on UID/GID mapping
  (`/etc/subuid`, `/etc/subgid`) and/or rootless networking (`/dev/net/tun`).
- If you only have rootless Podman available, expect Airlock smoke tests to skip and builds to be unreliable.
  See `docs/throwaway-container-test.md` for a detailed log of the issues we hit.

## Testing (Repo)

```bash
make test
```

Notes:

- If you hit missing-tool errors, run `make deps-check` (or `make deps-apt` on Debian/Ubuntu).
- `./scripts/test-system.sh` reuses an existing `airlock-agent:local` image when present; force rebuild with
  `AIRLOCK_SYSTEM_REBUILD=1 ./scripts/test-system.sh`.
- `./scripts/test-system-dind.sh` is an explicit smoke path for `yolo --dind` (it will skip if the engine
  can’t run privileged containers).
- `make help` shows the full SDLC target list.

See `docs/getting-started.md` for the full tutorial.

## Contributing

See `CONTRIBUTING.md`.

## License

MIT (see `LICENSE`).
