# Airlock Decisions (Living Notes)

This file records “why” decisions made while building Airlock, so future sessions don’t lose context.

## Defaults are convenience-first (with escape hatches)

- Default engine is `podman` (override: `AIRLOCK_ENGINE=docker|nerdctl`).
- `yolo` runs without preconfiguration:
  - Mounts host `~/.codex/` into the container (rw) so Codex auth/config works on first run.
  - Mounts host OpenCode state (`~/.config/opencode/` and `~/.local/share/opencode/`) into the container (rw) so
    OpenCode auth/config works on first run.
  - Does **not** mount any additional project directories by default; extra mounts are explicit.

## “Don’t hide signals”

- Warnings/notices should lead to an explicit decision: **fix**, **pin**, or **document**.
- Avoid suppressing update notices (e.g., npm). Prefer explicit knobs like `AIRLOCK_NPM_VERSION`.

## Podman realities

- Podman builds can fail under OCI isolation in some systemd/integration environments; default to
  `podman build --isolation=chroot` (override: `AIRLOCK_BUILD_ISOLATION=...`).
- For “containers from inside `yolo`”, Airlock prefers socket passthrough (host engine) over nested engines.
- Airlock targets rootful engines. Rootless engines are currently unsupported (rootless Podman commonly fails
  on UID/GID mappings and/or `/dev/net/tun` networking).
- User namespace mappings can confuse git ownership checks. The container entrypoint sets git `safe.directory`
  for the workspace mount.

## Workdir stability (Codex resume collisions)

Mounting everything at the same in-container path makes different repos look identical to tools that key state
off the cwd.

- The default container cwd is a canonical `/host<host-path>` so state can’t collide between repos.

## Extra mounts (make them explicit)

- `yolo --mount-ro <DIR> -- ...` binds a host directory read-only at `/host<abs>`.
- `yolo --add-dir <DIR> -- ...` binds a host directory read-write at `/host<abs>`.
  - If the command is `codex`, Airlock also forwards each writable mount to Codex as `--add-dir /host<abs>`.

## Default mounts (state and cache)

Airlock keeps “project mounts” explicit, but it does mount a small set of tool state and caches by default so
agents work well across sessions:

- Codex: host `~/.codex/` → container `/home/airlock/.codex` (rw)
- OpenCode: host `~/.config/opencode/` and `~/.local/share/opencode/` → container (rw)
  - Opt out with `AIRLOCK_MOUNT_OPENCODE=0`
- Cache: host `~/.airlock/cache/` → container `~/.cache`/`~/.npm`/`~/.local/share/pnpm` (rw)
- Shell config: host `~/.airlock/config/zshrc` → container `~/.zshrc` (ro)

## Engine socket passthrough (Docker-outside-of-Docker)

Airlock will mount the host container engine socket when available so you can run builds from inside `yolo`.

- Convenience: you can build/run containers from inside the agent container without installing/configuring a nested engine.
- Risk: if the agent container can talk to the host engine socket, it can create other containers with different mounts and
  networking. Treat this as a high-trust feature.
- Escape hatch: disable with `airlock dock` (or `yolo --engine-socket=0` / `AIRLOCK_MOUNT_ENGINE_SOCKET=0`).
- Alternative (nested): disable socket passthrough and use Podman inside the `yolo` container.
  - This is slower and may be less compatible; `AIRLOCK_PODMAN_STORAGE_DRIVER=vfs` is the most portable option.
- Alternative (Docker-in-Docker): run a Docker daemon *inside* the `yolo` container.
  - Opt-in: `yolo --dind` (also via `AIRLOCK_DIND=1`)
  - Typically requires `--privileged` and a rootful outer engine (see `docs/docker-in-docker.md`).
  - This avoids mounting the host engine socket, but is still high-trust (privileged container).

## OAuth callbacks (port publishing)

Some agent CLIs start a local callback server during login. Airlock supports publishing ports via:

- `yolo --publish <SPEC>` (repeatable), or
- `AIRLOCK_PUBLISH_PORTS=spec1,spec2`

## Editing inside the agent container

The agent image sets `EDITOR=vi`/`VISUAL=vi` and installs an editor package (default: `vim-tiny`), so tools like Codex can
open an editor for multi-line prompts.

- Change editor package at build time: `AIRLOCK_EDITOR_PKG=vim-nox airlock-build`
