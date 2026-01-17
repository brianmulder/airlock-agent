# Development Checklist

Use this file as the task-level checklist for implementing the Airlock repo and workflow described in
`docs/roadmap.md`.

## Phase 0 — Host Prereqs

- [x] Confirm the container engine is running (`${AIRLOCK_ENGINE:-podman} info`)
- [x] Quality gate: `yolo` launches and shows the expected mounts
- [x] Document safety notes (dos and don’ts) for daily use
- [ ] DoD: Airlock runs end-to-end; safety guidance is documented and can be applied when desired

## Phase 1 — Repo Scaffold

- [x] Initialize git repo (if not already): `git init`
- [x] Create directories: `docs/`, `scripts/`, `stow/airlock/`
- [x] Add baseline docs: `README.md`
- [x] Add tutorial docs: `docs/getting-started.md`
- [x] Add threat model doc: `docs/threat-model.md`
- [x] Quality gate: docs label commands as “required” vs “example”
- [x] Quality gate: repo tree matches `docs/roadmap.md` design
- [x] DoD: repo is understandable and navigable (README + getting started + repo layout)

## Phase 2 — Stow Package (Installable Assets)

- [x] Add stow package skeleton under `stow/airlock/`
- [x] Add `stow/airlock/bin/airlock-build`
- [x] Add `stow/airlock/bin/airlock-doctor`
- [x] Add `stow/airlock/bin/yolo`
- [x] Add shell config under `stow/airlock/.airlock/config/`
- [x] Add image templates under `stow/airlock/.airlock/image/`
- [x] Add wrapper: `scripts/install.sh`
- [x] Add wrapper: `scripts/uninstall.sh`
- [x] Quality gate: `stow -d ./stow -t ~ airlock` is idempotent
- [x] Quality gate: `airlock-doctor` checks required files + key prerequisites
- [x] DoD: install/uninstall works cleanly via Stow

## Phase 3 — Agent Image (Devcontainer Base + Two‑Way Door)

- [x] Default base image is devcontainers node (documented + used in build)
- [x] Implement `agent.Dockerfile` with `BASE_IMAGE` + `CODEX_VERSION` build args
- [x] Install minimal extras (python venv tooling, UID/GID helper)
- [x] Implement `entrypoint.sh` UID/GID mapping via `AIRLOCK_UID`/`AIRLOCK_GID`
- [x] Quality gate: `airlock-build` succeeds on a clean machine
- [x] Quality gate: base image swap works via `AIRLOCK_BASE_IMAGE=...`
- [x] Quality gate: container boots and `codex --version` works
- [x] DoD: image is reproducible-ish and easily swappable

## Phase 4 — Launcher (`yolo`) + Mount Boundaries

- [x] `yolo` mounts workspace at `/host<host-path>` (rw) and uses a canonical `/host<host-path>` workdir by default
- [x] `yolo --mount-ro <DIR>`: bind-mounts host inputs read-only at `/host<abs>`
- [x] `yolo --add-dir <DIR>`: bind-mounts host outputs read-write at `/host<abs>` and forwards to Codex as `--add-dir`
- [x] Default Codex state: mount host `~/.codex/` (rw) into container
- [x] Default network = bridge; `AIRLOCK_NETWORK=host` is opt-in
- [x] Guardrail: pre-create host dirs to avoid root-owned folders
- [x] Git ergonomics: mount git repo root to `/host<path>` and use canonical workdir to avoid tool collisions
- [x] Git safety: container entrypoint sets `safe.directory` so `git status` works on bind mounts
- [x] Engine passthrough: host engine socket is mounted when available so container builds can run inside `yolo`
- [x] Quality gate (in container): with `--mount-ro`, writes fail
- [x] Quality gate (in container): with `--add-dir`, writes succeed
- [x] Quality gate (in container): `touch "$PWD/ok"` succeeds
- [x] Quality gate (in container): `mount` shows only expected explicit binds
- [x] DoD: RO mounts stay RO; RW mounts stay RW; nothing is implicit

## Phase 5 — Getting Started + Step-by-Step Tutorial

- [x] Write/refresh `docs/getting-started.md` as the canonical end-to-end tutorial
- [x] Add “promotion flow” steps (explicit writable dir → review → copy into repo)
- [x] Document dogfooding options in the guide (submodule vs vendoring)
- [x] Document safety notes inline in the guide
- [x] Quality gate: guide is copy/pasteable and matches `make test` smoke checks
- [x] Quality gate: paths are parameterized (no hard-coded usernames)
- [x] DoD: docs reproduce setup in a clean temp `$HOME` (see system smoke test)

## Phase 6 — Tests and Quality Gates (Lint / Unit / System)

- [x] Add local test entrypoints (`./scripts/test*.sh`)
- [x] Add `AIRLOCK_ENGINE` support (`podman|docker|nerdctl`) to scripts (default: `podman`)
- [x] Add optional Markdown linting (`.markdownlint-cli2.yaml` + `./scripts/test-lint.sh` best-effort)
- [ ] Add GitHub Actions workflow: run lint + unit (+ smoke where possible)
- [x] Quality gate: `./scripts/test.sh` passes (or clearly SKIPs missing system deps)
- [ ] Quality gate: CI passes on a clean runner
- [ ] DoD: regressions are caught before merge

## Phase 7 — Dogfood in Your Dotfiles Repo

- [x] Choose integration method: submodule (preferred) or vendoring
- [x] Stow Airlock from dotfiles repo into `$HOME`
- [x] Build image (`airlock-build`) and run `airlock-doctor`
- [ ] Use Airlock on a real project for at least one end-to-end change
- [x] Quality gate: no stow collisions (bin names, `~/.airlock` contents)
- [x] Quality gate: update loop is painless (pull/restow/rebuild as needed)
- [ ] DoD: daily use from dotfiles requires no manual hacks

## Phase 8 — Release + Maintenance

- [ ] Tag first release (e.g., `v0.1.0`) after dogfooding
- [ ] Publish repo to GitHub
- [x] Document upgrade/pinning: `AIRLOCK_CODEX_VERSION`, `AIRLOCK_BASE_IMAGE`
- [ ] Document “keep container engine updated” as an operational control
- [ ] DoD: stable starter release exists with a working tutorial

## Spec Addendum (v2.1 Errata)

- [x] Add `docs/spec-v2-1-addendum.md` capturing the errata checklist from `docs/roadmap.md`

## Project Definition of Done (Overall)

- [x] `stow -d <repo>/stow -t ~ airlock` installs binaries + templates
- [x] `airlock-build` produces a runnable image (default base + override)
- [x] `yolo` provides a writable workspace and explicit RO/RW mounts via flags
- [x] `airlock-doctor` passes on a standard Linux + container engine setup
- [x] `./scripts/test.sh` provides lint + unit + smoke coverage
- [x] `docs/getting-started.md` reproduces the setup end-to-end
