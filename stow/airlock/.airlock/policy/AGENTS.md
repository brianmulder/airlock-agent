# Airlock Agent Rules

- Workspace is /work. Treat it as the only editable source of truth.
- Context is /context and is read-only. Never attempt to modify it.
- Draft outputs go to /drafts.
- Prefer small diffs. Run tests/lint when reasonable.
- If you are unsure, write a patch to /drafts rather than editing tracked files.
