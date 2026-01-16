# Airlock Threat Model (Lightweight)

## Assets to Protect

- Windows host filesystem and personal data.
- Safe Haven context (read-only notes and references).
- Integrity of project repos.

## Trust Boundaries

- Windows host ↔ WSL manager environment
- WSL manager ↔ Docker agent container
- RO context (`/context`) ↔ RW outbox (`/drafts`)

## Assumptions

- Docker Desktop is kept up to date.
- WSL automount is disabled; only explicit mounts exist.
- The agent container can execute arbitrary code inside its sandbox.

## Primary Risks

- Over-broad mounts exposing Windows paths or secrets.
- RO context bypass by sharing a writable path on the same filesystem.
- Agent writes directly into the repo without review.

## Mitigations

- Disable WSL automount; mount only the context subfolder.
- Keep drafts on WSL ext4 (not under Dropbox/context).
- Make `/work` the only RW source of truth; rely on Git for rollback.
- Use `airlock-doctor` to validate environment assumptions.

## Residual Risk

- Docker is not a perfect security boundary.
- Misconfiguration can re-open host access.
- Agent can still damage the project repo; review and version control are the safety net.
