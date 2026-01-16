# Repository Guidelines

## Project Structure & Module Organization

- `chat-gpt-5.2-pro-extended-thinking.md`: the working technical specification for “The Airlock” (WSL + Docker “data diode” workflow).
- `docs/`: runbook, WSL hardening, threat model, spec addendum.
- `stow/airlock/`: GNU Stow package installed into `$HOME` (binaries + `~/.airlock` templates).
- `scripts/`: repo-local helpers (install/uninstall and test entrypoints).

## Build, Test, and Development Commands

- Lint + tests: `./scripts/test.sh`
- Lint only: `./scripts/test-lint.sh`
- Unit tests only (no container engine required): `./scripts/test-unit.sh`
- System smoke test (requires container engine + stow): `./scripts/test-system.sh`
- Engine selection: prefix commands with `AIRLOCK_ENGINE=docker|podman|nerdctl` (default: `docker`)

## Coding Style & Naming Conventions

- Markdown: use ATX headings (`#`, `##`), short sections, and fenced code blocks with language tags (e.g., ```bash).
- Diagrams: use Mermaid fenced blocks (```mermaid) and keep diagrams small enough to review in diffs.
- Prose: wrap text around ~100 characters where practical; don’t reflow code blocks.
- Names: new docs use `kebab-case.md`; user-facing scripts (when added) should be executable and follow `airlock-*` or `yolo*` naming.

## Testing Guidelines

- Prefer “sandboxed” validation: tests should use temporary directories and containers rather than touching real `$HOME`.
- Keep unit tests engine-free where possible (use `AIRLOCK_DRY_RUN=1` and stub engines like `AIRLOCK_ENGINE=true`).
- System tests should validate the full flow: stow → build → yolo → mount/network checks.

## Commit & Pull Request Guidelines

- Use Conventional Commits (e.g., `docs: …`, `feat: …`, `fix: …`).
- PRs should describe security impact (mounts, permissions, networking), link any related issue, and include diagram screenshots when visuals change.

## Security & Configuration Tips

- Never commit secrets (tokens, `.codex` contents, credential helpers).
- Prefer least-privilege defaults: avoid mounting broad host paths and avoid `--network host` unless explicitly required.
