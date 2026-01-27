# Configuration (Optional)

Airlock can read defaults from a TOML config file to reduce env-var sprawl and make “set-and-forget” dogfooding
easier.

## Location

- Default: `~/.airlock/config.toml`
- Override: set `AIRLOCK_CONFIG_TOML=/path/to/config.toml`

## Precedence

Airlock applies values in this order (highest to lowest):

1. CLI flags
2. Env vars
3. `config.toml` (including profile overrides)
4. Airlock built-in defaults

## Profiles

Profiles let you keep safer defaults for `airlock dock` while making `airlock yolo` intentionally higher-trust.

- `airlock dock` selects profile `dock`
- `airlock yolo` selects profile `yolo`
- `airlock build` selects profile `build`

Profiles are defined as `[profiles.<NAME>]` and override keys from `[airlock]` / `[build]`.

## Schema (supported keys)

```toml
[airlock]
engine = "podman"                 # AIRLOCK_ENGINE
image = "airlock-agent:local"     # AIRLOCK_IMAGE
network = "bridge"                # AIRLOCK_NETWORK ("host" enables host networking)
mount_style = "native"            # AIRLOCK_MOUNT_STYLE ("host-prefix" mounts under /host<abs>)
mount_opencode = true             # AIRLOCK_MOUNT_OPENCODE (0/1)
mount_engine_socket = false       # AIRLOCK_MOUNT_ENGINE_SOCKET (0/1)
add_dirs = []                     # AIRLOCK_ADD_DIRS (colon-joined)
mount_ros = []                    # AIRLOCK_MOUNT_ROS (colon-joined)
publish_ports = []                # AIRLOCK_PUBLISH_PORTS (comma-joined)

[build]
base_image = "mcr.microsoft.com/devcontainers/javascript-node:20-bookworm" # AIRLOCK_BASE_IMAGE
codex_version = "latest"          # AIRLOCK_CODEX_VERSION
opencode_version = "latest"       # AIRLOCK_OPENCODE_VERSION
npm_version = "latest"            # AIRLOCK_NPM_VERSION
editor_pkg = "vim-tiny"           # AIRLOCK_EDITOR_PKG
pull = true                       # AIRLOCK_PULL (0/1)
build_isolation = "chroot"        # AIRLOCK_BUILD_ISOLATION (podman only; optional)
build_userns = ""                 # AIRLOCK_BUILD_USERNS (podman only; optional)

[profiles.dock]
mount_engine_socket = false

[profiles.yolo]
mount_engine_socket = true
```

## Parser note

Airlock’s TOML loader uses `python3` with:

- `tomllib` (Python 3.11+), or
- `tomli` (if installed on older Python)

If TOML parsing isn’t available, Airlock will warn and continue using env vars + built-in defaults.

On Debian/Ubuntu (including WSL Ubuntu), a quick setup is:

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-tomli
```
