# Repository Guidelines

## Project Structure & Module Organization

- `chat-gpt-5.2-pro-extended-thinking.md`: the working technical specification for “The Airlock”.
- `docs/`: runbook, host hardening notes, threat model, spec addendum.
- `stow/airlock/`: GNU Stow package installed into `$HOME` (binaries + `~/.airlock` templates).
- `scripts/`: repo-local helpers (install/uninstall and test entrypoints).

## Build, Test, and Development Commands

- Lint + tests: `./scripts/test.sh`
- Lint only: `./scripts/test-lint.sh`
- Unit tests only (no container engine required): `./scripts/test-unit.sh`
- System smoke test (requires container engine + stow): `./scripts/test-system.sh`
- Engine selection: prefix commands with `AIRLOCK_ENGINE=podman|docker|nerdctl` (default: `podman`)
- Timing/debug: set `AIRLOCK_TIMING=1` to timestamp `yolo` + container entrypoint startup.
- Defaults: `yolo` mounts host `~/.codex/` (rw) and does not mount any extra directories unless explicitly requested (`--mount-ro`, `--add-dir`).
- Workdir: `yolo` sets the container working directory to a canonical `/host<host-path>` so tools don’t collide state across repos.
- Markdown lint: `./scripts/test-lint.sh` runs `markdownlint-cli2` if available (install: `npm i -g markdownlint-cli2`).
- Image build knobs:
  - `AIRLOCK_PULL=1|0` (default `1`)
  - `AIRLOCK_BUILD_ISOLATION=chroot|oci|...` (Podman defaults to `chroot` for compatibility)
  - `AIRLOCK_NPM_VERSION=latest|<ver>` (default `latest`)
 - Container builds inside `yolo`: `yolo` best-effort mounts the host engine socket so `podman`/`docker` commands work from inside the container.

## Coding Style & Naming Conventions

- Markdown: use ATX headings (`#`, `##`), short sections, and fenced code blocks with language tags (e.g., ```bash).
- Diagrams: use Mermaid fenced blocks (```mermaid) and keep diagrams small enough to review in diffs.
- Prose: wrap text around ~100 characters where practical; don’t reflow code blocks.
- Names: new docs use `kebab-case.md`; user-facing scripts (when added) should be executable and follow `airlock-*` or `yolo*` naming.

## Testing Guidelines

- Prefer “sandboxed” validation: tests should use temporary directories and containers rather than touching real `$HOME`.
- Keep unit tests engine-free where possible (use `AIRLOCK_DRY_RUN=1` and stub engines like `AIRLOCK_ENGINE=true`).
- System tests should validate the full flow: stow → build → yolo → mount/network checks.
- `./scripts/test-system.sh` auto-selects an engine when `AIRLOCK_ENGINE` is unset (prefers `podman`, then `docker`, then `nerdctl`).
- `./scripts/test-unit.sh` uses a repo-local venv (`./.venv/`) and requires Python 3.11+ (for `tomllib`); set `AIRLOCK_PYTHON_BIN=python3.11`.
- For stricter policy isolation, opt in to Airlock-managed Codex state: `AIRLOCK_CODEX_HOME_MODE=airlock yolo -- codex`.
- Treat warnings as actionable:
  - Podman may emit systemd/user-bus/cgroup warnings; use the system smoke test to decide if they’re harmless.
  - If Podman builds fail with `sd-bus`/`crun` errors, prefer `AIRLOCK_BUILD_ISOLATION=chroot`.

## Quality Principles

- Don’t hide signals: warnings/notices require an explicit decision (**fix**, **pin**, **document**)—not suppression.
- Prefer “modern by default, controllable by knobs”: keep defaults current (e.g., latest npm) and make pinning explicit (`AIRLOCK_NPM_VERSION`, `AIRLOCK_PULL`, etc.).
- Use local isolation to raise quality without host churn: if the distro lags (e.g., Python 3.10), use repo-local tooling (venv) rather than weakening checks.
- Make tradeoffs explicit: when choosing compatibility defaults (e.g., Podman `--isolation=chroot`), document the why and keep an escape hatch.

## Commit & Pull Request Guidelines

- Use Conventional Commits (e.g., `docs: …`, `feat: …`, `fix: …`).
- PRs should describe security impact (mounts, permissions, networking), link any related issue, and include diagram screenshots when visuals change.

## Security & Configuration Tips

- Never commit secrets (tokens, `.codex` contents, credential helpers).
- Prefer least-privilege defaults: avoid mounting broad host paths and avoid `--network host` unless explicitly required.
- For bind mounts, ensure host mount sources exist (`yolo` pre-creates cache subdirs like `~/.airlock/cache/npm`).
- Don’t silence tooling update notices; prefer pinning/controlling versions via explicit knobs (e.g., `AIRLOCK_NPM_VERSION`).
