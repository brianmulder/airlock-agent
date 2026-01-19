# WSL2: Rootful Docker + Rootful Podman Setup (for Airlock)

Airlock currently targets **rootful container engines**. On WSL2 it’s common to end up with a rootless Podman
setup (or a confusing “Docker CLI talking to Podman”), which causes hard-to-debug permission and networking
failures.

This guide captures a working path to get **both** Docker and Podman running **rootful** on WSL2, plus the
specific gotchas we hit along the way.

## 1) Enable systemd in your WSL distro (required)

Airlock needs a rootful daemon/socket that your user can access. On WSL2, the reliable way to run those
daemons is via systemd.

In WSL (inside Ubuntu/Debian):

```bash
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
```

From Windows PowerShell:

```powershell
wsl.exe --shutdown
```

Back in WSL:

```bash
ps -p 1 -o comm=
# expect: systemd
```

## 2) Docker (rootful) inside WSL

If you don’t want Docker Desktop, installing Docker Engine inside WSL works fine for Airlock:

```bash
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

Open a new shell (or restart WSL), then validate:

```bash
docker run --rm hello-world
```

### Docker “looks like Podman” (common WSL pitfall)

If `docker info` shows a suspicious server version (for example, `3.x`) and mentions Podman-ish details,
you likely have `podman-docker` installed. Remove it so `docker` is actually Docker:

```bash
sudo apt-get remove -y podman-docker
hash -r
docker version
```

## 3) Podman (rootful) exposed to your user

### 3.1 Enable the rootful Podman API socket

```bash
sudo apt-get update
sudo apt-get install -y podman
sudo systemctl enable --now podman.socket
```

The socket lives at:

- `/run/podman/podman.sock`

### 3.2 Fix the `/run/podman` permission trap

Even if the socket is correctly group-owned, Podman can still be unusable if the directory isn’t
traversable. The failure looks like:

```text
Error: unable to connect to Podman socket: ... dial unix /run/podman/podman.sock: connect: permission denied
```

Or:

```text
... connect: operation not permitted
```

Check the directory:

```bash
ls -ld /run/podman
```

If it’s `drwx------ root root`, your user can’t reach the socket.

On Debian/Ubuntu, a vendor tmpfiles rule can force this mode:

```bash
sudo grep -RIn "/run/podman" /usr/lib/tmpfiles.d /etc/tmpfiles.d || true
```

We observed:

```text
/usr/lib/tmpfiles.d/podman.conf: D! /run/podman 0700 root root
```

Override it by creating an `/etc` rule with the same path:

```bash
echo 'D! /run/podman 0755 root root' | sudo tee /etc/tmpfiles.d/podman.conf >/dev/null
sudo systemd-tmpfiles --create
```

### 3.3 Ensure the socket is group-accessible

Create a `podman` group, add your user, and configure the socket’s mode/group:

```bash
sudo groupadd -f podman
sudo usermod -aG podman "$USER"

sudo mkdir -p /etc/systemd/system/podman.socket.d
cat <<'EOF' | sudo tee /etc/systemd/system/podman.socket.d/10-airlock.conf >/dev/null
[Socket]
SocketGroup=podman
SocketMode=0660
EOF

sudo systemctl daemon-reload
sudo systemctl restart podman.socket
```

Now these should look like:

```bash
ls -ld /run/podman
ls -l /run/podman/podman.sock
# expect:
#   /run/podman is 0755 root:root (or similar, but traversable)
#   podman.sock is srw-rw---- root:podman
```

### 3.4 Make your shell pick up new groups

After `usermod -aG`, your current shell session may not have the new group. Validate with:

```bash
id | grep -q podman || newgrp podman
id | grep podman
```

### 3.5 Make `podman` use the rootful socket by default (recommended)

Rootful Podman is exposed via the rootful socket at `/run/podman/podman.sock`. A simple way to make your
user always talk to that socket is a small wrapper earlier in `PATH`:

```bash
mkdir -p ~/bin
cat <<'EOF' > ~/bin/podman
#!/usr/bin/env bash
exec /usr/bin/podman --remote --url unix:///run/podman/podman.sock "$@"
EOF
chmod +x ~/bin/podman
hash -r
```

Validate:

```bash
podman info | sed -n '1,40p'
podman run --rm hello-world
```

## 4) Airlock validation

Once Docker and/or rootful Podman are working:

```bash
airlock-wsl-prereqs

AIRLOCK_ENGINE=docker make test
AIRLOCK_ENGINE=docker make smoke-dind

AIRLOCK_ENGINE=podman make test
AIRLOCK_ENGINE=podman make smoke-dind
```

## 5) Quick troubleshooting map

- If `sudo podman info` works but `podman info` fails:
  - Check `/run/podman` permissions (`ls -ld /run/podman`).
  - Check socket ownership (`ls -l /run/podman/podman.sock`).
  - Check whether your shell has the `podman` group (`id` / `newgrp podman`).
- If `docker info` looks like Podman:
  - Remove `podman-docker` and confirm `docker version` reports Docker.

## 6) Disk footprint (WSL2 + container layers)

WSL’s `ext4.vhdx` expands as you pull/build images, but it does not shrink automatically when you delete
files. If you run into disk pressure:

```bash
# Inspect usage
podman system df
docker system df

# Safe-ish prune (dangling images / build cache / stopped containers)
podman system prune
docker system prune

# Nuclear option (destroys *all* Podman images/containers)
podman system reset --force
```

To reclaim space on Windows after deletes/prunes:

1. From PowerShell: `wsl.exe --shutdown`
2. Compact the VHDX (Windows `diskpart` → `compact vdisk`)
