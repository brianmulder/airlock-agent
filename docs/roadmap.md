# Roadmap

This roadmap turns the v2.1 “Airlock” spec in `docs/history/chatgpt-original-conversation-log.md` into a
stow-installable repo you can dogfood from your dotfiles.

## Goals

- Publish a repo at `~/code/github.com/brianmulder/airlock` that installs via GNU Stow.
- Provide a safe default workflow: writable mounts are the workspace plus tool state/cache mounts; any additional
  project host access is via explicit bind mounts (`yolo --mount-ro ...`, `yolo --add-dir ...`).
- Use a high-quality devcontainer base image by default, but keep it a “two-way door” (easy to swap).
- Support multiple container engines via `AIRLOCK_ENGINE` (default `podman`; also `docker`, `nerdctl`).
- Make first-run “just work” without env vars:
  - Use the host `~/.codex/` for Codex config/auth by default.
  - Use host caches under `~/.airlock/cache/` to keep builds snappy across sessions.

## Non-goals (v0.1)

- Claiming Docker is a perfect security boundary.
- Managing host OS setup for the user.
- Supporting every OS/desktop/container-engine permutation.

## Testing Strategy (Sandboxed)

Tests should be runnable without touching the real `$HOME` by using temporary directories and
ephemeral containers.

- Lint: `bash -n` and `shellcheck` (when installed) for all scripts.
- Unit tests: validate script behavior without a real engine by using `AIRLOCK_DRY_RUN=1` and stub
  engines (e.g., `AIRLOCK_ENGINE=true`).
- System smoke test: validate the full flow (stow → build → yolo → mount + network sanity checks),
  using a temp `$HOME`, a temp workspace, and explicit extra mounts. This must **not** run `codex`; it should prove
  the mechanics without the agent.
- Engine matrix: system test should run at least on `docker`; it should also be runnable on
  community-supported alternatives like `podman` and `nerdctl` when available.
  - Podman: prefer `podman build --isolation=chroot` when OCI isolation fails due to runtime integration issues.

## Track — Docker-in-Docker (DinD) Journey (Docker + Podman)

Airlock defaults to “Docker-outside-of-Docker” (mount the host engine socket) for convenience, but DinD is
a useful opt-in when a user prefers not to mount the host engine socket.

The goal is to support DinD across the common engine matrix with clear, testable expectations:

1. Docker engine (rootful): primary DinD target. `yolo --dind` should work end-to-end.
2. Podman rootful: secondary DinD target. `yolo --dind` should work (privileged outer container).
3. Rootless engines: explicitly unsupported (document why + point users to Docker).
4. Tests: add an explicit system smoke path that exercises `yolo --dind` so it can be validated in CI/dev.

## Phase 0 — Prereqs and Baseline Validation

This phase is mostly “host setup”. Airlock is designed to run without special project mounts by default, but
usage guidance should be explicit about what to mount (and what not to).

1. Confirm environment assumptions:
   - A Linux environment with a working container engine.
2. Quality gates (minimum):
   - `yolo` launches and shows only explicit mounts.
   - `${AIRLOCK_ENGINE:-podman} info` works from the host shell.
3. Documentation:
   - Add a short “dos and don’ts” guide for daily usage (secrets, mounts, networking, engine socket).

Definition of done:

- Airlock runs end-to-end; safety guidance is documented and can be applied when desired.

## Phase 1 — Repo Scaffold

1. Initialize repository layout:
   - `docs/` for a getting started guide + security notes.
   - `scripts/` for helper installers.
   - `stow/airlock/` for everything installable into `$HOME`.
2. Add baseline docs:
   - `README.md` with quickstart and threat model summary.
   - `docs/getting-started.md`, `docs/threat-model.md`.
3. Quality gates:
   - All commands in docs are copy/pasteable and labelled “required” vs “example”.
   - Directory tree matches the repo design in the spec.

Definition of done:

- A new contributor can understand the workflow and where files live.

## Phase 2 — Stow Package (Installable Assets)

1. Implement stow package contents under `stow/airlock/`:
   - `bin/airlock-build`, `bin/airlock-doctor`, `bin/yolo`
   - `~/.airlock/config/` templates: minimal `zshrc`
   - `~/.airlock/image/` templates: `agent.Dockerfile`, `entrypoint.sh`
2. Add `scripts/install.sh` and `scripts/uninstall.sh` wrappers for stow.
3. Quality gates:
   - `stow -d ./stow -t ~ airlock` is idempotent (repeatable with no surprises).
   - `airlock-doctor` validates required files and key environmental prerequisites.
   - Unit tests pass without a running container engine (`./scripts/test-unit.sh`).

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
   - Ensure git works on bind mounts by setting `safe.directory` for the workspace mount.
4. Quality gates:
   - `airlock-build` succeeds on a clean machine (no local assumptions).
   - Base image swap works: build succeeds with `AIRLOCK_BASE_IMAGE=...`.
   - Container boots into zsh and `codex --version` works.

Definition of done:

- Image builds reproducibly and is easy to swap without code changes.

## Phase 4 — Launcher (`yolo`) + Mount Boundaries

1. Implement `yolo` to enforce invariants:
   - The workspace mount is RW and is the git repo root when inside a repo (so `.git/` is available from subdirs).
   - Default working directory is a canonical `/host<host-path>` so tools like Codex don’t conflate different repos.
   - No implicit “extra” mounts. Additional host access is explicit:
     - Read-only inputs: `yolo --mount-ro <DIR> -- ...` (mounted at `/host<abs>`).
     - Read-write dirs: `yolo --add-dir <DIR> -- ...` (mounted at `/host<abs>` and forwarded to Codex as `--add-dir`).
   - Default Codex state is host `~/.codex/` (rw) so auth/config “just works”.
   - Default network = bridge; `AIRLOCK_NETWORK=host` is opt-in.
2. Guardrails:
   - Create host directories up front to avoid root-owned folders.
   - Make `git status` work by setting git `safe.directory` inside the container.
3. Quality gates (manual checks run inside container):
   - With `yolo --mount-ro <DIR> -- ...`, `touch /host<DIR>/nope` fails.
   - With `yolo --add-dir <DIR> -- ...`, `touch /host<DIR>/ok` succeeds.
   - `touch "$PWD/ok"` succeeds.
   - No unintentional host path mounts are present (`mount` output only shows explicit binds).
   - Smoke test can run without the agent: `yolo -- bash -lc '...'`.

Definition of done:

- The “data diode” behavior is real in practice: inputs can be mounted RO; outputs can be mounted RW; nothing is implicit.

## Phase 5 — Getting Started + Tutorial (Step-by-Step)

1. Write `docs/getting-started.md` as the canonical tutorial:
   - Install, image build, doctor checks, daily workflow, promotion flow.
   - Dogfooding options:
     - submodule in dotfiles (`vendor/airlock`) + stow from there
     - vendoring the stow package directly
2. Include safety notes in the guide (short, actionable, and opt-in).
3. Quality gates:
   - The guide is copy/pasteable and matches the system smoke test assertions.
   - All paths are parameterized (no hard-coded usernames).

Definition of done:

- Documentation is sufficient to reproduce the setup on a new machine.

## Phase 6 — Tests and Quality Gates (Lint / Unit / System)

1. Add local test entrypoints:
   - `./scripts/test-lint.sh` (bash syntax + shellcheck when available)
   - `./scripts/test-unit.sh` (engine-free validation)
   - `./scripts/test-system.sh` (smoke test: stow → build → yolo → checks)
   - `./scripts/test.sh` (runs all of the above)
2. System smoke test requirements:
   - Uses a temp `$HOME`, a temp workspace, and explicit RO/RW extra mounts.
   - Runs `yolo` with a command override (no interactive prompt required).
   - Validates RO/RW mounts and basic network namespace config (bridge by default).
3. Engine support requirements:
   - Add `AIRLOCK_ENGINE` to scripts (`airlock-build`, `airlock-doctor`, `yolo`).
   - Test matrix: `podman` preferred; `docker`/`nerdctl` best-effort if installed.
4. Add CI (recommended):
   - Run lint + unit tests on every PR.
   - Run system smoke test on a runner with a working engine.
5. Quality gates:
   - `./scripts/test.sh` passes locally (or produces clear SKIP output for missing system deps).
   - CI passes for lint + unit; system smoke passes in at least one engine environment.

Definition of done:

- Regressions in scripts/config/stow/container plumbing are caught before merge.

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
   - Update cadence for Docker Desktop / alternative engines and base images.
   - How to pin Codex CLI version (`AIRLOCK_CODEX_VERSION`).

Definition of done:

- A stable “starter release” exists with a working tutorial and predictable upgrades.

## Errata / Addendum Checklist for Spec v2.1

Create `docs/spec-v2-1-addendum.md` capturing at least:

- Devcontainers base as default (`mcr.microsoft.com/devcontainers/*`) instead of raw `node:*`.
- Portable UID/GID mapping via `AIRLOCK_UID`/`AIRLOCK_GID` + entrypoint.
- `CODEX_HOME` as the containment boundary; config is TOML at `config.toml`.
- Host networking is opt-in (and Docker Desktop requires enabling it).
- Writable outputs should be host-local and mounted explicitly (e.g., via `yolo --add-dir ...`).
- Any absolute security claims should be rewritten to precise, testable statements.

## Overall Definition of Done (Project)

- `stow -d <repo>/stow -t ~ airlock` installs: `yolo`, `airlock-build`, `airlock-doctor`, and
  `~/.airlock/{config,image}` templates.
- `airlock-build` produces a runnable image (default base + overrideable base).
- `yolo` launches a container with a writable workspace and no implicit extra mounts; RO/RW behavior is defined by flags.
- `airlock-doctor` passes on a standard Linux + container engine setup.
- `./scripts/test.sh` provides lint + unit + smoke coverage for stow/image/yolo mechanics.
- Docs in `docs/getting-started.md` reproduce the setup end-to-end.
