# Airlock Spec v2.1 — Addendum / Errata

This addendum aligns the v2.1 spec with the repository implementation and Stow-based workflow.

## A) Devcontainer Base Image (Default)

- Default base image: `mcr.microsoft.com/devcontainers/javascript-node:20-bookworm`.
- Rationale: includes common dev tooling and a non-root user; reduces custom Dockerfile work.
- Two-way door: override via `AIRLOCK_BASE_IMAGE=...` at build time.

## B) UID/GID Portability

- Do not assume UID 1000.
- Entry point maps `AIRLOCK_UID`/`AIRLOCK_GID` to a runtime user inside the container.
- Prevents permission issues when host UID/GID differ.

## C) Codex Config Boundary

- Codex config is TOML at `~/.codex/config.toml` (or under `CODEX_HOME`).
- `CODEX_HOME` is treated as the containment boundary for agent state.

## D) Host Networking Is Opt‑In

- Default network is Docker bridge.
- `AIRLOCK_NETWORK=host` explicitly enables host networking.
- On Docker Desktop, host networking requires enabling the feature.

## E) Drafts Must Be Host‑Local

- Keep writable outputs host-local (prefer a Linux filesystem) and mount them explicitly via `yolo --add-dir ...`.
- Avoid making the same host tree both read-only and writable via different mounts.
- Prevents RO‑bypass via same-filesystem writable paths and avoids syncing unreviewed outputs.

## F) Security Claims Must Be Precise

- Avoid absolutes (“cannot compromise host”).
- State testable boundaries: “Agent can only access mounted paths.”
