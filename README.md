# Airlock

Airlock is a compartmentalized dev workflow for AI-assisted coding on Windows + WSL + Docker.
It separates a safe **manager environment** (WSL) from an **execution environment** (ephemeral
Docker container), with a strict filesystem boundary and a review-first outbox.

## Quickstart

1. Install prerequisites (WSL2, Docker Desktop, Dropbox).
2. Apply WSL hardening and mount only your context folder (see `docs/WSL_HARDENING.md`).
3. Install Airlock via GNU Stow:

```bash
sudo apt-get update && sudo apt-get install -y stow
stow -d ~/code/github.com/brianmulder/airlock/stow -t ~ airlock
hash -r
```

4. Build the agent image:

```bash
airlock-build
```

5. Run the doctor checks:

```bash
airlock-doctor
```

6. Launch the agent from a WSL-native repo:

```bash
cd ~/code/your-project
yolo
```

Inside the container:

```bash
codex
```

## Repository Layout

- `docs/` – runbook and security notes
- `scripts/` – install/uninstall helpers
- `stow/airlock/` – installable package (binaries + templates)

## Key Design Rules

- `/context` is read-only and mounted from Dropbox.
- `/drafts` is read-write on WSL ext4 (quarantine for agent outputs).
- `/work` is the only editable source of truth (project repo).
- Host networking is opt-in (`AIRLOCK_NETWORK=host`).

See `docs/RUNBOOK.md` for the full tutorial.
