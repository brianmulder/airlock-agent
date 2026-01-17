# Airlock

Airlock is a compartmentalized dev workflow for AI-assisted coding on a Linux host + containers
(Podman/Docker/nerdctl). It runs an ephemeral container with explicit mounts and a review-first workflow.

Operational safety notes: see `docs/dos-and-donts.md` and `docs/threat-model.md`.

## Quickstart

1. Install prerequisites: a container engine (GNU Stow optional).
1. Install Airlock via GNU Stow (adjust the repo path as needed):

```bash
mkdir -p ~/.airlock ~/bin
sudo apt-get update && sudo apt-get install -y stow
stow -d ~/code/github.com/brianmulder/airlock/stow -t ~ airlock
hash -r
```

Or (recommended):

```bash
./scripts/install.sh
```

If stow isn’t an option, `./scripts/install.sh` will install via symlinks; see `docs/getting-started.md`.

1. Build the agent image:

```bash
airlock-build
```

1. Launch from a project repo:

```bash
cd ~/code/your-project
yolo
```

Tip: if you run `yolo` again from the same directory while the container is still running, it will attach.
Use `yolo --new` to start a second container.

Launch Codex:

```bash
yolo -- codex
```

Launch OpenCode:

```bash
yolo -- opencode
```

Authentication note:

- By default, `yolo` mounts your host `~/.codex/` into the container (rw), so your login/config “just works”.
- By default, `yolo` mounts your host OpenCode state (`~/.config/opencode/` and `~/.local/share/opencode/`) into the
  container (rw), so your auth/config persists across runs.
- If OpenCode login redirects to `http://localhost:1455/...` (OAuth callback), publish that port:

```bash
yolo --publish 1455:1455 -- opencode auth login
```

Mount additional directories explicitly:

```bash
# Read-only inputs
yolo --mount-ro ~/tmp/inputs -- codex

# Extra writable directory (also forwarded to `codex --add-dir ...`)
yolo --add-dir ~/tmp/airlock-writes -- codex
```

## Global Agent Notes

Codex also reads `~/.codex/AGENTS.md` for global instructions. A reasonable baseline for `yolo` containers:

```markdown
- If `$AIRLOCK_YOLO=1`, you are inside an Airlock `yolo` container.
- Your filesystem access is defined by explicit bind mounts; ask the user where outputs should go if unsure.
```

Engine selection examples:

```bash
AIRLOCK_ENGINE=podman airlock-build
AIRLOCK_ENGINE=podman yolo
AIRLOCK_EDITOR_PKG=vim-nox airlock-build
```

## Note for WSL users

Airlock itself is Linux-first and does not require WSL-specific configuration. If you use it on WSL2, treat
any Windows-mounted paths as “untrusted” by default: keep your workspace and writable mounts on the Linux
filesystem, and mount Windows-backed inputs read-only (e.g., via `yolo --mount-ro ...`).

## Note for Dropbox users

Dropbox is optional. If you want a sync-backed inputs folder, mount it read-only:

```bash
yolo --mount-ro ~/path/to/dropbox/inputs -- codex
```

## Repository Layout

- `docs/` – getting started guide and security notes
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

## Key Design Rules

- By default, writable mounts are your workspace plus tool state/cache mounts (e.g., `~/.codex/`).
- Additional project mounts are explicit (`yolo --mount-ro ...` / `yolo --add-dir ...`).
- Host networking is opt-in (`AIRLOCK_NETWORK=host`).
- `yolo` mounts the git repo root (or the current directory) at a canonical `/host<host-path>` so tools don’t conflate repos.

## Containers From Inside `yolo`

Airlock mounts the host engine socket when available so you can run container builds from inside the `yolo`
shell (e.g., `docker build ...`). This is convenient but high-trust; disable it when you don’t need it:

```bash
yolo --no-engine-socket
```

If you disable the socket mount and still need to build/run containers from inside `yolo`, you can try nested
Podman (daemonless). It will be slower and may be less compatible; `vfs` storage is the most portable:

```bash
AIRLOCK_MOUNT_ENGINE_SOCKET=0 AIRLOCK_PODMAN_STORAGE_DRIVER=vfs yolo
```

Note: when the host engine is Podman, `docker` talking to the Podman socket is often more reliable than
`podman --remote` because it avoids Podman client/server version skew.

## Testing (Repo)

```bash
make test
```

Notes:

- If you hit missing-tool errors, run `make deps-check` (or `make deps-apt` on Debian/Ubuntu).
- `./scripts/test-system.sh` reuses an existing `airlock-agent:local` image when present; force rebuild with
  `AIRLOCK_SYSTEM_REBUILD=1 ./scripts/test-system.sh`.
- `make help` shows the full SDLC target list.

See `docs/getting-started.md` for the full tutorial.

## Contributing

See `CONTRIBUTING.md`.

## License

MIT (see `LICENSE`).
