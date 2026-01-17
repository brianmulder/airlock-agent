# Airlock

Airlock is a compartmentalized dev workflow for AI-assisted coding on Windows + WSL + Docker.
It separates a safe **manager environment** (WSL) from an **execution environment** (ephemeral
Docker container), with a strict filesystem boundary and a review-first outbox.

## Quickstart

1. Install prerequisites (WSL2, a container engine, Dropbox).
2. Apply WSL hardening and mount only your context folder (see `docs/WSL_HARDENING.md`).
3. Install Airlock via GNU Stow (adjust the repo path as needed):

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

4. Ensure your context directory exists. By default, `yolo` uses `~/tmp/airlock_context` (created automatically).
   If you’re using a mounted Dropbox context, override:

```bash
export AIRLOCK_CONTEXT_DIR=~/dropbox/fred
```

5. Build the agent image:

```bash
airlock-build
```

6. Run the doctor checks:

```bash
airlock-doctor
```

7. Launch the agent from a WSL-native repo:

```bash
cd ~/code/your-project
yolo
```

Inside the container:

```bash
codex
```

Authentication note:
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

Engine selection examples:

```bash
AIRLOCK_ENGINE=podman airlock-build
AIRLOCK_ENGINE=podman yolo
```

## Repository Layout

- `docs/` – runbook and security notes
- `scripts/` – install/uninstall helpers
- `stow/airlock/` – installable package (binaries + templates)

## Key Design Rules

- `/context` is read-only and mounted from your chosen context directory (often a mounted Dropbox folder).
- `/drafts` is read-write on WSL ext4 (quarantine for agent outputs).
- `/work` is the only editable source of truth (project repo).
- Host networking is opt-in (`AIRLOCK_NETWORK=host`).
- `yolo` mounts the git repo root to `/work` when run inside a repo (so `.git/` is available even from subdirs).
- By default, the container working directory is a canonical `/host<WSL-path>` so tools don’t conflate different repos that would otherwise all look like `/work`.

## Testing (Repo)

```bash
./scripts/test.sh
```

Notes:
- `./scripts/test-unit.sh` bootstraps a repo-local venv at `./.venv/` using Python 3.11+ (for `tomllib`).
  Set `AIRLOCK_PYTHON_BIN=python3.11` if needed.

See `docs/RUNBOOK.md` for the full tutorial.
