# Airlock Tracking Sheet

Use this file as the task-level checklist for implementing the Airlock repo and workflow described in
`PLAN.md`.

## Phase 0 — Prereqs and Baseline Validation

- [ ] Confirm Windows 11 + WSL2 working
- [ ] Confirm Docker Desktop running + WSL integration enabled
- [ ] Confirm Dropbox is installed and synced on Windows
- [ ] Create a dedicated context subfolder (e.g., `Dropbox\\fred`)
- [ ] Update `/etc/wsl.conf` (disable automount; optional interop disable)
- [ ] Update `/etc/fstab` (mount only the context subfolder into WSL)
- [ ] Run `wsl --shutdown` and reopen the distro
- [ ] Quality gate: no surprise Windows mounts under `/mnt/*`
- [ ] Quality gate: context mount exists at `~/dropbox/fred` (or configured path)
- [ ] Quality gate: `docker info` succeeds from WSL
- [ ] DoD: WSL is “manager-safe” and context is explicitly mounted

## Phase 1 — Repo Scaffold

- [ ] Initialize git repo (if not already): `git init`
- [ ] Create directories: `docs/`, `scripts/`, `stow/airlock/`
- [ ] Add baseline docs: `README.md`
- [ ] Add tutorial docs: `docs/RUNBOOK.md`
- [ ] Add WSL hardening doc: `docs/WSL_HARDENING.md`
- [ ] Add threat model doc: `docs/THREAT_MODEL.md`
- [ ] Quality gate: docs label commands as “required” vs “example”
- [ ] Quality gate: repo tree matches `PLAN.md` design
- [ ] DoD: repo is understandable and navigable for new contributors

## Phase 2 — Stow Package (Installable Assets)

- [ ] Add stow package skeleton under `stow/airlock/`
- [ ] Add `stow/airlock/bin/airlock-build`
- [ ] Add `stow/airlock/bin/airlock-doctor`
- [ ] Add `stow/airlock/bin/yolo`
- [ ] Add policy templates under `stow/airlock/.airlock/policy/`
- [ ] Add image templates under `stow/airlock/.airlock/image/`
- [ ] Add wrapper: `scripts/install.sh`
- [ ] Add wrapper: `scripts/uninstall.sh`
- [ ] Quality gate: `stow -d ./stow -t ~ airlock` is idempotent
- [ ] Quality gate: `airlock-doctor` checks required files + key prerequisites
- [ ] DoD: install/uninstall works cleanly via Stow

## Phase 3 — Agent Image (Devcontainer Base + Two‑Way Door)

- [ ] Default base image is devcontainers node (documented + used in build)
- [ ] Implement `agent.Dockerfile` with `BASE_IMAGE` + `CODEX_VERSION` build args
- [ ] Install minimal extras (python venv tooling, UID/GID helper)
- [ ] Implement `entrypoint.sh` UID/GID mapping via `AIRLOCK_UID`/`AIRLOCK_GID`
- [ ] Quality gate: `airlock-build` succeeds on a clean machine
- [ ] Quality gate: base image swap works via `AIRLOCK_BASE_IMAGE=...`
- [ ] Quality gate: container boots and `codex --version` works
- [ ] DoD: image is reproducible-ish and easily swappable

## Phase 4 — Launcher (`yolo`) + Policy Boundaries

- [ ] `yolo` mounts: `/work` (rw), `/context` (ro), `/drafts` (rw on WSL ext4)
- [ ] Persist Codex state via `CODEX_HOME` under `~/.airlock/codex-state`
- [ ] Default network = bridge; `AIRLOCK_NETWORK=host` is opt-in
- [ ] Guardrail: fail if drafts live under context dir (no same-filesystem RO bypass)
- [ ] Guardrail: pre-create host dirs to avoid root-owned folders
- [ ] Quality gate (in container): `touch /context/nope` fails
- [ ] Quality gate (in container): `touch /drafts/ok` succeeds
- [ ] Quality gate (in container): `touch /work/ok` succeeds
- [ ] Quality gate (in container): `mount` shows only expected explicit binds
- [ ] DoD: RO context stays RO; artifacts land in quarantine outbox

## Phase 5 — Runbook + Step-by-Step Tutorial

- [ ] Write/refresh `docs/RUNBOOK.md` as the canonical end-to-end tutorial
- [ ] Add “promotion flow” steps (drafts → review → copy into repo/Dropbox)
- [ ] Document dogfooding options in runbook (submodule vs vendoring)
- [ ] Write/refresh `docs/WSL_HARDENING.md` with exact snippets + rollback steps
- [ ] Quality gate: a fresh user can follow the runbook end-to-end without guessing
- [ ] Quality gate: paths are parameterized (no hard-coded usernames)
- [ ] DoD: docs reproduce setup on a new WSL install

## Phase 6 — Quality Gates Automation (Recommended)

- [ ] Add `shellcheck` checks for `stow/airlock/bin/*` and `scripts/*`
- [ ] Add optional Markdown linting command and/or CI target
- [ ] Add GitHub Actions workflow (optional): run checks on PRs
- [ ] Quality gate: CI passes on a clean runner
- [ ] Quality gate: scripts are bash-only or clearly documented otherwise
- [ ] DoD: regressions are caught before merge

## Phase 7 — Dogfood in Your Dotfiles Repo

- [ ] Choose integration method: submodule (preferred) or vendoring
- [ ] Stow Airlock from dotfiles repo into `$HOME`
- [ ] Build image (`airlock-build`) and run `airlock-doctor`
- [ ] Use Airlock on a real project for at least one end-to-end change
- [ ] Quality gate: no stow collisions (bin names, `~/.airlock` contents)
- [ ] Quality gate: update loop is painless (pull/restow/rebuild as needed)
- [ ] DoD: daily use from dotfiles requires no manual hacks

## Phase 8 — Release + Maintenance

- [ ] Tag first release (e.g., `v0.1.0`) after dogfooding
- [ ] Document upgrade/pinning: `AIRLOCK_CODEX_VERSION`, `AIRLOCK_BASE_IMAGE`
- [ ] Document “keep Docker Desktop updated” as an operational control
- [ ] DoD: stable starter release exists with a working tutorial

## Spec Addendum (v2.1 Errata)

- [ ] Add `docs/SPEC_v2.1_ADDENDUM.md` capturing the errata checklist from `PLAN.md`

## Project Definition of Done (Overall)

- [ ] `stow -d <repo>/stow -t ~ airlock` installs binaries + templates
- [ ] `airlock-build` produces a runnable image (default base + override)
- [ ] `yolo` enforces RO `/context` and RW `/drafts` on WSL ext4
- [ ] `airlock-doctor` passes on a standard WSL2 + Docker Desktop setup
- [ ] `docs/RUNBOOK.md` reproduces the setup end-to-end
