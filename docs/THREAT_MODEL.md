# Airlock Threat Model (Lightweight)

## Assets to Protect

- Host filesystem and personal data.
- Any host directories you bind-mount into the container.
- Integrity of project repos.

## Trust Boundaries

- Host ↔ “manager” shell environment
- Manager ↔ container engine runtime
- Read-only mounts (`yolo --mount-ro ...`) ↔ writable mounts (workspace + `yolo --add-dir ...`)

## Assumptions

- Container engine is kept up to date.
- Only explicit mounts exist (no surprise broad host mounts into the container).
- The agent container can execute arbitrary code inside its sandbox.

## Primary Risks

- Over-broad mounts exposing Windows paths or secrets.
- Read-only boundary bypass by accidentally making the same host tree writable.
- Agent writes directly into the repo without review.

## Mitigations

- Keep mounts narrow and explicit (prefer `--mount-ro` for inputs).
- Prefer a dedicated writable outbox mounted via `--add-dir` for artifacts you’ll review.
- Treat the workspace mount as writable; rely on Git for rollback.
- Use `airlock-doctor` and the system smoke test (`./scripts/test-system.sh`) to validate plumbing.

## Residual Risk

- Docker is not a perfect security boundary.
- Misconfiguration can re-open host access.
- Agent can still damage the project repo; review and version control are the safety net.
