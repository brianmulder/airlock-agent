# Airlock Threat Model (Lightweight)

This is a concise threat model intended to keep daily usage safe and predictable.

## Assets to Protect

- Host filesystem and personal data.
- Any host directories you bind-mount into the container.
- Integrity of project repos.
- Credentials and secrets (SSH keys, cloud tokens, API keys).

## Trust Boundaries

- Host ↔ “manager” shell environment
- Manager ↔ container engine runtime
- Read-only mounts (`yolo --mount-ro ...`) ↔ writable mounts (workspace + `yolo --add-dir ...`)
- Host ↔ container engine socket passthrough (when enabled)

## Assumptions

- Container engine is kept up to date.
- Only explicit mounts exist (no surprise broad host mounts into the container).
- The agent container can execute arbitrary code inside its sandbox.

## Primary Risks

- Over-broad mounts exposing Windows paths or secrets.
- Read-only boundary bypass by accidentally making the same host tree writable.
- Agent writes directly into the repo without review.
- If the container can access the host engine socket, it can create additional containers with different mounts/networking.

## Mitigations

- Keep mounts narrow and explicit (prefer `--mount-ro` for inputs).
- Prefer putting agent outputs in an explicitly mounted writable directory (`yolo --add-dir ...`) so you can
  review them on the host before copying into your repo.
- Treat the workspace mount as writable; rely on Git for rollback.
- Use `airlock-doctor` and the system smoke test (`./scripts/test-system.sh`) to validate plumbing.
- Keep credentials out of the workspace and out of mounts (avoid mounting `$HOME`, `~/.ssh`, `~/.aws`, etc.).
- If you don’t need to build/run containers from inside `yolo`, disable engine socket passthrough:

```bash
AIRLOCK_MOUNT_ENGINE_SOCKET=0 yolo
```

## Docker-outside-of-Docker (Engine Socket Passthrough)

When `yolo` mounts the host engine socket (e.g., Docker’s `/var/run/docker.sock`), the container can ask the
host engine to create other containers with different mounts and network settings.

This is convenient, but it is not a “small” permission: treat it as equivalent to giving the agent very broad
control over what the host engine can do.

Mitigation: disable it with `AIRLOCK_MOUNT_ENGINE_SOCKET=0` unless you explicitly need it.

## Residual Risk

- Docker is not a perfect security boundary.
- Misconfiguration can re-open host access.
- Agent can still damage the project repo; review and version control are the safety net.
- Engine socket passthrough is a high-trust convenience feature; treat `yolo` as having “host-user-level” power when enabled.
