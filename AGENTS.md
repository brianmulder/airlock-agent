# Repository Guidelines

## Project Structure & Module Organization

- `chat-gpt-5.2-pro-extended-thinking.md`: the working technical specification for “The Airlock” (WSL + Docker “data diode” workflow).
- If you add more documentation, prefer grouping it under `docs/` (e.g., `docs/architecture.md`, `docs/threat-model.md`) to keep the repo root tidy.
- If/when automation is added, use:
  - `scripts/` for runnable helpers (e.g., `scripts/yolo`, `scripts/preflight`)
  - `config/` for templates/snippets (e.g., `config/wsl.conf`, `config/fstab`)

## Build, Test, and Development Commands

This repository is currently documentation-only (no checked-in build/test runner).

- Optional Markdown lint: `npx markdownlint-cli2 "**/*.md"` (requires Node) or your preferred linter.
- Docker/WSL commands live in the spec; keep them copy-pasteable and clearly labeled as **examples** vs **required** steps.

## Coding Style & Naming Conventions

- Markdown: use ATX headings (`#`, `##`), short sections, and fenced code blocks with language tags (e.g., ```bash).
- Diagrams: use Mermaid fenced blocks (```mermaid) and keep diagrams small enough to review in diffs.
- Prose: wrap text around ~100 characters where practical; don’t reflow code blocks.
- Names: new docs use `kebab-case.md`; user-facing scripts (when added) should be executable and follow `airlock-*` or `yolo*` naming.

## Testing Guidelines

- No automated tests yet. If you add code/scripts, include a minimal smoke test and document a single entrypoint to run it (e.g., `./scripts/test.sh`).

## Commit & Pull Request Guidelines

- Git history isn’t available in this checkout; default to Conventional Commits (e.g., `docs: …`, `feat: …`, `fix: …`).
- PRs should describe security impact (mounts, permissions, networking), link any related issue, and include diagram screenshots when visuals change.

## Security & Configuration Tips

- Never commit secrets (tokens, `.codex` contents, credential helpers).
- Prefer least-privilege defaults: avoid mounting broad host paths and avoid `--network host` unless explicitly required.
