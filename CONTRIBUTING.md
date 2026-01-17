# Contributing

Airlock is a security-oriented workflow: defaults should stay least-privilege, knobs should be explicit, and
docs/tests should match reality.

## Development

Prereqs:

- `bash`, `make`, `git`
- `node` + `npx` (used for Markdown lint fallback)
- `shellcheck`
- `stow` (for system smoke test)
- One container engine: `podman` (default), `docker`, or `nerdctl`

## Testing

Mandatory for all changes:

```bash
make test
```

Targeted commands:

```bash
make lint
make unit
make smoke
```

Engine selection:

```bash
AIRLOCK_ENGINE=docker make test
```

## Style

- Shell scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, and keep `shellcheck` clean.
- Markdown: ATX headings (`#`, `##`), fenced code blocks with language tags, wrap prose around ~100 chars.

## Policy: Defaults and Safety

- Don’t add new writable mounts by default without a clear reason and an opt-out knob.
- Prefer “two-way doors”: ship safe defaults, and make pinning/overrides explicit via env vars.
- Don’t hide signals: warnings should lead to an explicit decision (**fix**, **pin**, or **document**).

## Commits / PRs

- Use Conventional Commits (e.g., `feat: …`, `fix: …`, `docs: …`).
- PRs should describe security impact (mounts, permissions, networking) and how the change was tested.
