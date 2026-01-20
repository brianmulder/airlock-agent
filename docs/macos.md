# macOS (Experimental)

Airlock is Linux-first. macOS support is **experimental** and currently best-effort.

If you try it on macOS, expect sharp edges around the host shell/tooling (GNU vs BSD userland) and the container
engine (Docker Desktop vs VM-backed engines).

## Recommended setup (Docker Desktop)

Airlock assumes a **rootful** engine and Linux-like sockets. On macOS, the best match is typically Docker Desktop.

1) Install Docker Desktop (and ensure `docker info` works).
2) Install required host tools via Homebrew (recommended).

## Homebrew (quick install)

```bash
brew install bash coreutils stow shellcheck node python
brew install --cask docker
```

## PATH gotchas (GNU tools)

Airlock scripts assume GNU-ish behavior for a few common utilities:

- `bash` (macOS ships Bash 3.2; Airlock uses modern Bash features)
- `readlink -f` (not supported by BSD `readlink`)
- `sort -z` (not supported by BSD `sort`)

With Homebrew `bash` and `coreutils`, you usually just need to ensure Homebrew is early in `PATH` and GNU coreutils
are on-path.

Add something like this to your shell config (zsh):

```bash
if command -v brew >/dev/null 2>&1; then
  export PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"
fi
```

Sanity checks:

```bash
command -v bash
bash --version | head -n 1
readlink -f . >/dev/null
sort --version >/dev/null
docker info >/dev/null
```

## Engine notes

- Recommended: `AIRLOCK_ENGINE=docker` (Docker Desktop).
- Podman on macOS typically runs via `podman machine` (remote). Airlock’s engine socket passthrough expects a local
  socket path and is not tuned for Podman-machine setups yet.

## Known caveats

- Bind-mount performance can be slower on macOS than on Linux (especially large repos / `node_modules`).
- Apple Silicon vs x86_64: base images are usually multi-arch, but if you hit an amd64-only dependency you may need
  to pick a different base image.
- `make test` system smoke tests may behave differently than Linux due to engine/VM differences.

## Quick smoke test (macOS)

```bash
./scripts/install.sh
AIRLOCK_ENGINE=docker airlock-build

cd /path/to/your/repo
AIRLOCK_ENGINE=docker airlock dock -- bash -lc 'id; git status --porcelain'
```

If you hit issues, include:

- `bash --version` (first line)
- `command -v bash readlink sort docker`
- `docker version`
