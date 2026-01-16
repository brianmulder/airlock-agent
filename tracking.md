# Airlock Tracking Sheet

Use this file as the task-level checklist for implementing the Airlock repo and workflow described in
`PLAN.md`.

## Phase 0 — Prereqs and Baseline Validation

- [ ] Confirm Windows 11 + WSL2 working
- [ ] Confirm container engine running + WSL integration enabled
- [ ] Confirm Dropbox is installed and synced on Windows
- [ ] Create a dedicated context subfolder (e.g., `Dropbox\\fred`)
- [ ] Update `/etc/wsl.conf` (disable automount; optional interop disable)
- [ ] Update `/etc/fstab` (mount only the context subfolder into WSL)
- [ ] Run `wsl --shutdown` and reopen the distro
- [ ] Quality gate: no surprise Windows mounts under `/mnt/*`
- [ ] Quality gate: context mount exists at `~/dropbox/fred` (or configured path)
- [ ] Quality gate: `${AIRLOCK_ENGINE:-docker} info` succeeds from WSL
- [ ] DoD: WSL is “manager-safe” and context is explicitly mounted

## Phase 1 — Repo Scaffold

- [x] Initialize git repo (if not already): `git init`
- [x] Create directories: `docs/`, `scripts/`, `stow/airlock/`
- [x] Add baseline docs: `README.md`
- [x] Add tutorial docs: `docs/RUNBOOK.md`
- [x] Add WSL hardening doc: `docs/WSL_HARDENING.md`
- [x] Add threat model doc: `docs/THREAT_MODEL.md`
- [x] Quality gate: docs label commands as “required” vs “example”
- [x] Quality gate: repo tree matches `PLAN.md` design
- [ ] DoD: repo is understandable and navigable for new contributors

## Phase 2 — Stow Package (Installable Assets)

- [x] Add stow package skeleton under `stow/airlock/`
- [x] Add `stow/airlock/bin/airlock-build`
- [x] Add `stow/airlock/bin/airlock-doctor`
- [x] Add `stow/airlock/bin/yolo`
- [x] Add policy templates under `stow/airlock/.airlock/policy/`
- [x] Add image templates under `stow/airlock/.airlock/image/`
- [x] Add wrapper: `scripts/install.sh`
- [x] Add wrapper: `scripts/uninstall.sh`
- [x] Quality gate: `stow -d ./stow -t ~ airlock` is idempotent
- [ ] Quality gate: `airlock-doctor` checks required files + key prerequisites
- [ ] DoD: install/uninstall works cleanly via Stow

## Phase 3 — Agent Image (Devcontainer Base + Two‑Way Door)

- [x] Default base image is devcontainers node (documented + used in build)
- [x] Implement `agent.Dockerfile` with `BASE_IMAGE` + `CODEX_VERSION` build args
- [x] Install minimal extras (python venv tooling, UID/GID helper)
- [x] Implement `entrypoint.sh` UID/GID mapping via `AIRLOCK_UID`/`AIRLOCK_GID`
- [ ] Quality gate: `airlock-build` succeeds on a clean machine
- [ ] Quality gate: base image swap works via `AIRLOCK_BASE_IMAGE=...`
- [ ] Quality gate: container boots and `codex --version` works
- [ ] DoD: image is reproducible-ish and easily swappable

## Phase 4 — Launcher (`yolo`) + Policy Boundaries

- [x] `yolo` mounts: `/work` (rw), `/context` (ro), `/drafts` (rw on WSL ext4)
- [x] Persist Codex state via `CODEX_HOME` under `~/.airlock/codex-state`
- [x] Default network = bridge; `AIRLOCK_NETWORK=host` is opt-in
- [x] Guardrail: fail if drafts live under context dir (no same-filesystem RO bypass)
- [x] Guardrail: pre-create host dirs to avoid root-owned folders
- [ ] Quality gate (in container): `touch /context/nope` fails
- [ ] Quality gate (in container): `touch /drafts/ok` succeeds
- [ ] Quality gate (in container): `touch /work/ok` succeeds
- [ ] Quality gate (in container): `mount` shows only expected explicit binds
- [ ] DoD: RO context stays RO; artifacts land in quarantine outbox

## Phase 5 — Runbook + Step-by-Step Tutorial

- [x] Write/refresh `docs/RUNBOOK.md` as the canonical end-to-end tutorial
- [x] Add “promotion flow” steps (drafts → review → copy into repo/Dropbox)
- [x] Document dogfooding options in runbook (submodule vs vendoring)
- [x] Write/refresh `docs/WSL_HARDENING.md` with exact snippets + rollback steps
- [ ] Quality gate: a fresh user can follow the runbook end-to-end without guessing
- [x] Quality gate: paths are parameterized (no hard-coded usernames)
- [ ] DoD: docs reproduce setup on a new WSL install

## Phase 6 — Tests and Quality Gates (Lint / Unit / System)

- [x] Add local test entrypoints (`./scripts/test*.sh`)
- [x] Add `AIRLOCK_ENGINE` support (`docker|podman|nerdctl`) to scripts
- [ ] Add optional Markdown linting command and/or CI target
- [ ] Add GitHub Actions workflow: run lint + unit (+ smoke where possible)
- [x] Quality gate: `./scripts/test.sh` passes (or clearly SKIPs missing system deps)
- [ ] Quality gate: CI passes on a clean runner
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
- [ ] Document “keep container engine updated” as an operational control
- [ ] DoD: stable starter release exists with a working tutorial

## Spec Addendum (v2.1 Errata)

- [x] Add `docs/SPEC_v2.1_ADDENDUM.md` capturing the errata checklist from `PLAN.md`

## Project Definition of Done (Overall)

- [ ] `stow -d <repo>/stow -t ~ airlock` installs binaries + templates
- [ ] `airlock-build` produces a runnable image (default base + override)
- [ ] `yolo` enforces RO `/context` and RW `/drafts` on WSL ext4
- [ ] `airlock-doctor` passes on a standard WSL2 + container engine setup
- [ ] `./scripts/test.sh` provides lint + unit + smoke coverage
- [ ] `docs/RUNBOOK.md` reproduces the setup end-to-end
