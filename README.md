# Airlock

Airlock is a compartmentalized dev workflow for AI-assisted coding on a Linux host + containers
(Podman/Docker/nerdctl). It runs an ephemeral container with explicit mounts and a review-first workflow.

## Quickstart

1. Install prerequisites: a container engine and GNU Stow.
2. Install Airlock via GNU Stow (adjust the repo path as needed):

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

3. Build the agent image:

```bash
airlock-build
```

4. Launch from a project repo:

```bash
cd ~/code/your-project
yolo
```

Launch Codex:

```bash
yolo -- codex
```

Authentication note:
- By default, `yolo` mounts your host `~/.codex/` into the container (rw), so your login/config “just works”.
- If you prefer Airlock-managed state under `~/.airlock/codex-state/` (with policy overrides), opt in:

```bash
AIRLOCK_CODEX_HOME_MODE=airlock yolo -- codex
```

Mount additional directories explicitly:

```bash
# Read-only inputs
yolo --mount-ro ~/tmp/inputs -- codex

# Extra writable directory (also forwarded to `codex --add-dir ...`)
yolo --add-dir ~/tmp/outbox -- codex
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
```

## Note for WSL users

Airlock itself is Linux-first and does not require WSL-specific configuration. If you use it on WSL2, treat
any Windows-mounted paths as “untrusted” by default: keep your workspace and writable mounts on the Linux
filesystem, and mount Windows-backed inputs read-only (e.g., via `yolo --mount-ro ...`).

If you want the stronger “manager hardening” setup (no automatic Windows drive mounts + optional narrow
mount), see `docs/WSL_HARDENING.md`.

## Note for Dropbox users

Dropbox is optional. If you want a sync-backed inputs folder, mount it read-only:

```bash
yolo --mount-ro ~/path/to/dropbox/inputs -- codex
```

## Repository Layout

- `docs/` – runbook and security notes
- `scripts/` – install/uninstall helpers
- `stow/airlock/` – installable package (binaries + templates)
- `docs/DECISIONS.md` – living “why” notes (defaults, tradeoffs, troubleshooting)

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

- By default, only your workspace mount is writable inside the container.
- Additional mounts are explicit (`yolo --mount-ro ...` / `yolo --add-dir ...`).
- Host networking is opt-in (`AIRLOCK_NETWORK=host`).
- `yolo` mounts the git repo root (or the current directory) at a canonical `/host<host-path>` so tools don’t conflate repos.

## Containers From Inside `yolo`

Airlock mounts the host engine socket when available so you can run container builds from inside the `yolo`
shell (e.g., `docker build ...`). If the socket isn’t present, run `airlock-doctor` for the suggested setup.

Note: when the host engine is Podman, `docker` talking to the Podman socket is often more reliable than
`podman --remote` because it avoids Podman client/server version skew.

## Testing (Repo)

```bash
./scripts/test.sh
```

Notes:
- `./scripts/test-unit.sh` bootstraps a repo-local venv at `./.venv/` using Python 3.11+ (for `tomllib`).
  Set `AIRLOCK_PYTHON_BIN=python3.11` if needed.

See `docs/RUNBOOK.md` for the full tutorial.
