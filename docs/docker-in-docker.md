# Docker-in-Docker (DinD) in `yolo`

Airlock’s default approach for “containers from inside `yolo`” is **socket passthrough**
(Docker-outside-of-Docker): mount the host engine socket into the agent container.

For users who prefer not to mount the host engine socket, Airlock also supports an **opt-in**
Docker-in-Docker mode: start a Docker daemon inside the `yolo` container.

## Quickstart

Start `yolo` with DinD enabled:

```bash
yolo --dind -- bash -lc 'docker version; docker info'
```

Then you can build/run “inner” containers from inside the `yolo` shell using `docker`:

```bash
docker run --rm hello-world
```

## How it works

When you pass `--dind`:

- `yolo` runs the container **privileged** and disables host socket mounting.
- The agent image entrypoint starts `dockerd` in the background.
- The entrypoint still drops to your host UID/GID for your interactive shell/command (so workspace writes
  remain owned by you), but the Docker daemon runs as root inside the container.

Knobs:

- `AIRLOCK_DIND=1` (equivalent to `--dind`)
- `AIRLOCK_DIND_STORAGE_DRIVER=vfs|overlay2|...` (default: `vfs`)
- `AIRLOCK_DIND_DOCKERD_ARGS="..."` (extra `dockerd` args; whitespace-split)

## Limitations / gotchas

- DinD requires a **rootful outer engine** that can run privileged containers (e.g., Docker, or rootful
  Podman). Airlock does not support rootless engines at this time.
- DinD is **not supported in a rootless user namespace**. If you see:

  ```text
  ERROR: AIRLOCK_DIND=1 is not supported in a rootless user namespace.
  ```

  Use a rootful outer engine and avoid user namespace remapping / rootless engines.

- Prefer `docker` inside the container when using DinD. (`podman` inside the container is a separate,
  “nested Podman” mode.)

## Security note

DinD does **not** mount the host engine socket, but it still runs the `yolo` container privileged.
Treat it as a high-trust option.
