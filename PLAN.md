# Airlock Implementation Plan

This plan turns the v2.1 “Airlock” spec in `chat-gpt-5.2-pro-extended-thinking.md` into a
stow-installable repo that you can dogfood from your dotfiles.

## Goals

- Publish a repo at `~/code/github.com/brianmulder/airlock` that installs via GNU Stow.
- Provide a safe default workflow: RO context (`/context`), RW workspace (`/work`), RW outbox (`/drafts`)
  on WSL ext4 (not inside Dropbox).
- Use a high-quality devcontainer base image by default, but keep it a “two-way door” (easy to swap).

## Non-goals (v0.1)

- Claiming Docker is a perfect security boundary.
- Managing Dropbox/WSL/Docker Desktop installation for the user.
- Supporting every shell/OS combination outside Windows + WSL2.

## Phase 0 — Prereqs and Baseline Validation

1. Confirm environment assumptions:
   - Windows 11 + WSL2 distro available.
   - Docker Desktop installed, running, and WSL integration enabled.
   - Dropbox folder present on Windows, and a dedicated context subfolder exists (e.g. `Dropbox\\fred`).
2. Apply WSL hardening (documented steps):
   - `/etc/wsl.conf`: disable automount; optionally disable interop.
   - `/etc/fstab`: mount only the context subfolder (not all of Dropbox).
3. Quality gates:
   - After `wsl --shutdown`, WSL does **not** auto-mount Windows drives under `/mnt/*`.
   - Context mount exists at `~/dropbox/fred` (or configured path).
   - `docker info` works from WSL.

Definition of done:
- WSL is “manager-safe” (no surprise `/mnt/c`) and Dropbox context is mounted explicitly.

## Phase 1 — Repo Scaffold

1. Initialize repository layout:
   - `docs/` for runbook + security notes.
   - `scripts/` for helper installers.
   - `stow/airlock/` for everything installable into `$HOME`.
2. Add baseline docs:
   - `README.md` with quickstart and threat model summary.
   - `docs/RUNBOOK.md`, `docs/WSL_HARDENING.md`, `docs/THREAT_MODEL.md`.
3. Quality gates:
   - All commands in docs are copy/pasteable and labelled “required” vs “example”.
   - Directory tree matches the repo design in the spec.

Definition of done:
- A new contributor can understand the workflow and where files live.

## Phase 2 — Stow Package (Installable Assets)

1. Implement stow package contents under `stow/airlock/`:
   - `bin/airlock-build`, `bin/airlock-doctor`, `bin/yolo`
   - `~/.airlock/policy/` templates: `codex.config.toml`, `AGENTS.md`, minimal `zshrc`
   - `~/.airlock/image/` templates: `agent.Dockerfile`, `entrypoint.sh`
2. Add `scripts/install.sh` and `scripts/uninstall.sh` wrappers for stow.
3. Quality gates:
   - `stow -d ./stow -t ~ airlock` is idempotent (repeatable with no surprises).
   - `airlock-doctor` validates required files and key environmental prerequisites.

Definition of done:
- A user can install/uninstall cleanly with Stow (or via `scripts/install.sh`).

## Phase 3 — Agent Image (Devcontainer Base + Two‑Way Door)

1. Use a devcontainers base image by default (from the spec plan):
   - Default `BASE_IMAGE=mcr.microsoft.com/devcontainers/javascript-node:20-bookworm`.
   - Keep override via env/build args: `AIRLOCK_BASE_IMAGE=...`.
2. Implement `agent.Dockerfile` with:
   - `ARG BASE_IMAGE` and `ARG CODEX_VERSION`.
   - Minimal extras: Python 3 + venv tooling, `gosu` (or equivalent) for UID/GID mapping.
   - Install Codex CLI: `npm i -g @openai/codex@${CODEX_VERSION}`.
3. Implement `entrypoint.sh` to:
   - Create or reuse a user matching host `AIRLOCK_UID`/`AIRLOCK_GID`.
   - Ensure `HOME` and `CODEX_HOME` are stable.
4. Quality gates:
   - `airlock-build` succeeds on a clean machine (no local assumptions).
   - Base image swap works: build succeeds with `AIRLOCK_BASE_IMAGE=...`.
   - Container boots into zsh and `codex --version` works.

Definition of done:
- Image builds reproducibly and is easy to swap without code changes.

## Phase 4 — Launcher (`yolo`) + Policy Boundaries

1. Implement `yolo` to enforce invariants:
   - `/context` is RO (Dropbox-mounted context folder).
   - `/drafts` is RW but stored on WSL ext4 (`~/.airlock/outbox/drafts`).
   - `/work` is RW and is the current repo directory.
   - Persist Codex state via `CODEX_HOME` under `~/.airlock/codex-state`.
   - Default network = bridge; `AIRLOCK_NETWORK=host` is opt-in.
2. Guardrails:
   - Fail fast if drafts live under the context directory (prevents RO-bypass footguns).
   - Create host directories up front to avoid root-owned folders.
3. Quality gates (manual checks run inside container):
   - `touch /context/nope` fails.
   - `touch /drafts/ok` succeeds.
   - `touch /work/ok` succeeds.
   - No unintentional host path mounts are present (`mount` output only shows explicit binds).

Definition of done:
- The “data diode” behavior is real in practice: RO context stays RO; artifacts land in quarantine.

## Phase 5 — Runbook + Tutorial (Step-by-Step)

1. Write `docs/RUNBOOK.md` as the canonical tutorial:
   - WSL hardening steps, Stow install, image build, doctor checks, daily workflow, promotion flow.
   - Dogfooding options:
     - submodule in dotfiles (`vendor/airlock`) + stow from there
     - vendoring the stow package directly
2. Write `docs/WSL_HARDENING.md` with exact file snippets for:
   - `/etc/wsl.conf`
   - `/etc/fstab`
   - recovery steps (how to undo / restore interop if needed)
3. Quality gates:
   - A fresh user can follow the runbook end-to-end without guessing.
   - All paths are parameterized (no hard-coded usernames).

Definition of done:
- Documentation is sufficient to reproduce the setup on a new WSL install.

## Phase 6 — Quality Gates Automation (Recommended)

1. Add lightweight checks (local + CI where possible):
   - `shellcheck` for `bin/*` and `scripts/*`
   - Markdown linting (optional)
2. Add a GitHub Actions workflow to run the checks on PRs (optional but high leverage).
3. Quality gates:
   - CI passes on a clean runner.
   - Scripts remain POSIX-ish (or clearly marked as bash-only).

Definition of done:
- Regressions in scripts/docs are caught before merge.

## Phase 7 — Dogfood in Your Dotfiles Repo

1. Integrate Airlock via submodule (preferred) or vendoring.
2. Stow into `$HOME`, build image, run doctor, and use on a real project.
3. Quality gates:
   - No conflicts with existing stow packages (bin collisions, `.airlock` collisions).
   - Iterative updates are painless (pull submodule → restow → rebuild if needed).

Definition of done:
- You can use Airlock daily from your dotfiles workflow without manual hacks.

## Phase 8 — Release + Maintenance

1. Tag a first release (e.g., `v0.1.0`) after dogfooding.
2. Document maintenance expectations:
   - Update cadence for Docker Desktop and base images.
   - How to pin Codex CLI version (`AIRLOCK_CODEX_VERSION`).

Definition of done:
- A stable “starter release” exists with a working tutorial and predictable upgrades.

## Errata / Addendum Checklist for Spec v2.1

Create `docs/SPEC_v2.1_ADDENDUM.md` capturing at least:

- Devcontainers base as default (`mcr.microsoft.com/devcontainers/*`) instead of raw `node:*`.
- Portable UID/GID mapping via `AIRLOCK_UID`/`AIRLOCK_GID` + entrypoint.
- `CODEX_HOME` as the containment boundary; config is TOML at `config.toml`.
- Host networking is opt-in (and Docker Desktop requires enabling it).
- Drafts must be on WSL ext4 and manually promoted into Dropbox after review.
- Any absolute security claims should be rewritten to precise, testable statements.

## Overall Definition of Done (Project)

- `stow -d <repo>/stow -t ~ airlock` installs: `yolo`, `airlock-build`, `airlock-doctor`, and
  `~/.airlock/{policy,image}` templates.
- `airlock-build` produces a runnable image (default base + overrideable base).
- `yolo` launches a container that enforces RO `/context` and RW `/drafts` on ext4.
- `airlock-doctor` passes on a standard WSL2 + Docker Desktop setup.
- Docs in `docs/RUNBOOK.md` reproduce the setup end-to-end.
