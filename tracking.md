# Airlock Tracking Sheet

Use this file as the task-level checklist for implementing the Airlock repo and workflow described in
`PLAN.md`.

## Phase 0 — Host Prereqs (Optional Hardening)

- [ ] Confirm the container engine is running (`${AIRLOCK_ENGINE:-podman} info`)
- [ ] Quality gate: `yolo` launches and shows the expected mounts
- [ ] Optional hardening: apply platform-specific mount hardening (see `docs/WSL_HARDENING.md` for one example)
- [ ] DoD: Airlock runs end-to-end; hardening is documented and can be applied when desired

## Phase 1 — Repo Scaffold

- [x] Initialize git repo (if not already): `git init`
- [x] Create directories: `docs/`, `scripts/`, `stow/airlock/`
- [x] Add baseline docs: `README.md`
- [x] Add tutorial docs: `docs/RUNBOOK.md`
- [x] Add host hardening doc (platform example): `docs/WSL_HARDENING.md`
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
- [ ] DoD: install/uninstall works cleanly via Stow (install confirmed; uninstall pending)

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

- [x] `yolo` mounts workspace at `/host<host-path>` (rw) and uses a canonical `/host<host-path>` workdir by default
- [x] `yolo --mount-ro <DIR>`: bind-mounts host inputs read-only at `/host<abs>`
- [x] `yolo --add-dir <DIR>`: bind-mounts host outputs read-write at `/host<abs>` and forwards to Codex as `--add-dir`
- [x] Default Codex state: mount host `~/.codex/` (rw) into container
- [x] Strict mode: `AIRLOCK_CODEX_HOME_MODE=airlock` persists state under `~/.airlock/codex-state` with policy overrides
- [x] Default network = bridge; `AIRLOCK_NETWORK=host` is opt-in
- [x] Guardrail: pre-create host dirs to avoid root-owned folders
- [x] Git ergonomics: mount git repo root to `/host<path>` and use canonical workdir to avoid tool collisions
- [x] Git safety: container entrypoint sets `safe.directory` so `git status` works on bind mounts
- [x] Engine passthrough: host engine socket is mounted when available so container builds can run inside `yolo`
- [ ] Quality gate (in container): with `--mount-ro`, writes fail
- [ ] Quality gate (in container): with `--add-dir`, writes succeed
- [ ] Quality gate (in container): `touch "$PWD/ok"` succeeds
- [ ] Quality gate (in container): `mount` shows only expected explicit binds
- [ ] DoD: RO mounts stay RO; RW mounts stay RW; nothing is implicit

## Phase 5 — Runbook + Step-by-Step Tutorial

- [x] Write/refresh `docs/RUNBOOK.md` as the canonical end-to-end tutorial
- [x] Add “promotion flow” steps (outbox → review → copy into repo)
- [x] Document dogfooding options in runbook (submodule vs vendoring)
- [x] Write/refresh `docs/WSL_HARDENING.md` (platform example) with exact snippets + rollback steps
- [ ] Quality gate: a fresh user can follow the runbook end-to-end without guessing
- [x] Quality gate: paths are parameterized (no hard-coded usernames)
- [ ] DoD: docs reproduce setup on a new machine

## Phase 6 — Tests and Quality Gates (Lint / Unit / System)

- [x] Add local test entrypoints (`./scripts/test*.sh`)
- [x] Add `AIRLOCK_ENGINE` support (`podman|docker|nerdctl`) to scripts (default: `podman`)
- [x] Add optional Markdown linting (`.markdownlint-cli2.yaml` + `./scripts/test-lint.sh` best-effort)
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
- [ ] Publish repo to GitHub
- [ ] Document upgrade/pinning: `AIRLOCK_CODEX_VERSION`, `AIRLOCK_BASE_IMAGE`
- [ ] Document “keep container engine updated” as an operational control
- [ ] DoD: stable starter release exists with a working tutorial

## Spec Addendum (v2.1 Errata)

- [x] Add `docs/SPEC_v2.1_ADDENDUM.md` capturing the errata checklist from `PLAN.md`

## Project Definition of Done (Overall)

- [ ] `stow -d <repo>/stow -t ~ airlock` installs binaries + templates
- [ ] `airlock-build` produces a runnable image (default base + override)
- [ ] `yolo` provides a writable workspace and explicit RO/RW mounts via flags
- [ ] `airlock-doctor` passes on a standard Linux + container engine setup
- [ ] `./scripts/test.sh` provides lint + unit + smoke coverage
- [ ] `docs/RUNBOOK.md` reproduces the setup end-to-end
