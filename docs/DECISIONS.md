# Decisions (Living Notes)

This file records “why” decisions made while building Airlock, so future sessions don’t lose context.

## Defaults are convenience-first (with escape hatches)

- Default engine is `podman` (override: `AIRLOCK_ENGINE=docker|nerdctl`).
- `yolo` runs without preconfiguration:
  - Mounts host `~/.codex/` into the container (rw) so Codex auth/config works on first run.
  - Does **not** mount any extra directories by default; additional mounts are explicit.
- Stricter mode is opt-in:
  - `AIRLOCK_CODEX_HOME_MODE=airlock yolo` persists Codex state under `~/.airlock/codex-state/` and mounts
    `config.toml` read-only into `CODEX_HOME`.

## “Don’t hide signals”

- Warnings/notices should lead to an explicit decision: **fix**, **pin**, or **document**.
- Avoid suppressing update notices (e.g., npm). Prefer explicit knobs like `AIRLOCK_NPM_VERSION`.

## Podman realities

- Podman builds can fail under OCI isolation in some systemd/integration environments; default to
  `podman build --isolation=chroot` (override: `AIRLOCK_BUILD_ISOLATION=...`).
- For “containers from inside `yolo`”, Airlock prefers socket passthrough (host engine) over nested engines.
- Rootless/userns mappings can confuse git ownership checks. The container entrypoint sets git
  `safe.directory` for the workspace mount.

## Workdir stability (Codex resume collisions)

Mounting everything at the same in-container path makes different repos look identical to tools that key state
off the cwd.

- The default container cwd is a canonical `/host<host-path>` so state can’t collide between repos.

## Extra mounts (make them explicit)

- `yolo --mount-ro <DIR> -- ...` binds a host directory read-only at `/host<abs>`.
- `yolo --add-dir <DIR> -- ...` binds a host directory read-write at `/host<abs>`.
  - If the command is `codex`, Airlock also forwards each writable mount to Codex as `--add-dir /host<abs>`.
