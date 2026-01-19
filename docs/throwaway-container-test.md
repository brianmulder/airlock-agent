# Throwaway Container Build/Run Test (Podman)

This document records a one-off “can we build and run *any* container here?” smoke test performed from
this repo, including the issues encountered and the workarounds used.

Status: Airlock does **not** support rootless engines at this time. This writeup is kept as a historical
record of what went wrong and what worked in a constrained rootless Podman environment.

## Date

- 2026-01-18

## Environment (as observed during the run)

- Engine CLI: `podman` (`/usr/local/bin/podman`, a wrapper that falls back to `/usr/bin/podman`)
- Podman version: `4.3.1`
- Podman mode: rootless (per `podman info`)
- Kernel: `6.6.87.2-microsoft-standard-WSL2` (per `podman info`)
- Storage driver: `vfs` (per `podman info`)

Key warning from `podman version`:

```text
Using rootless single mapping into the namespace. This might break some images.
Check /etc/subuid and /etc/subgid for adding sub*ids if not using a network user
```

## What I tried first (Airlock’s system smoke test)

Airlock already has a system-level smoke test that exercises the
“stow → build → yolo → mount checks” flow:

```bash
./scripts/test-system.sh
```

On the first run it succeeded using an existing `airlock-agent:local` image and launched a `yolo` container,
then validated the expected read-only/read-write mounts and basic network route presence.

On a later run (and especially when forcing rebuilds), the test failed during image pull/build because Podman
could not apply layers that require non-trivial UID/GID ownership.

## Issues encountered (and what they looked like)

### 1) Rootless “single mapping” UID/GID breaks many pulls/builds

`podman info` showed idMappings where container ID `0` maps to host ID `0` with `size: 1` for both UID and
GID. In practice, that means layers that need files owned by other IDs (e.g., `0:42`, `65534:65534`, etc.)
cannot be applied.

Symptoms when pulling common small images:

- `alpine:3.19` pull failed with:

  ```text
  potentially insufficient UIDs or GIDs available in user namespace (requested 0:42 for /etc/shadow)
  ... lchown /etc/shadow: invalid argument
  ```

- `busybox:1.36` pull failed with:

  ```text
  potentially insufficient UIDs or GIDs available in user namespace (requested 65534:65534 for /home)
  ... lchown /home: invalid argument
  ```

And it also broke rebuilding the Airlock agent image from its usual base:

```text
... potentially insufficient UIDs or GIDs available in user namespace (requested 0:42 for /etc/gshadow)
... lchown /etc/gshadow: invalid argument
```

### 2) Rootless networking failed (`/dev/net/tun` missing)

Even when an image pull succeeded, `podman run` failed trying to start rootless networking via
`slirp4netns`:

```text
/usr/bin/slirp4netns failed: "open(\"/dev/net/tun\"): No such file or directory
...
"
```

### 3) Disabling networking triggered a hostname permission error

Attempting to avoid `slirp4netns` by disabling networking:

```bash
podman run --rm --network none hello-world
```

Failed with:

```text
runc create failed: ... sethostname: operation not permitted: OCI permission denied
```

## What worked (throwaway build + run)

Because many base images could not be pulled due to the user namespace mapping, the workaround was to use a
base image that *did* pull successfully in this environment (`hello-world`), and then build a tiny derived
image from it.

### Step 1: Pull + run the base image (with flags)

Pulling `hello-world` succeeded, but running it required:

- `--network none` to avoid the `/dev/net/tun` + `slirp4netns` failure, and
- `--uts host` to avoid the `sethostname` permission failure.

Working run:

```bash
podman run --rm --uts host --network none hello-world
```

### Step 2: Create a minimal Dockerfile under `.airlock-test-tmp/`

I created a temporary build context inside the repo’s `.airlock-test-tmp/` directory (it’s in
`.gitignore`). In this run, the directory happened to be `.airlock-test-tmp/throwaway.JBCic5`.

```bash
tmp="$(mktemp -d -p .airlock-test-tmp throwaway.XXXXXX)"
cat > "$tmp/Dockerfile" <<'EOF'
FROM hello-world:latest
LABEL purpose="airlock-throwaway-test"
EOF
```

### Step 3: Build (matching Airlock’s preferred isolation)

Airlock defaults Podman builds to chroot isolation for compatibility, so the throwaway build used the same:

```bash
podman build --isolation chroot -t airlock-throwaway:test "$tmp"
```

### Step 4: Run the throwaway image

```bash
podman run --rm --uts host --network none airlock-throwaway:test
```

This printed the expected `hello-world` output, proving “build + run” works end-to-end with the above
constraints.

### Cleanup

```bash
podman rmi airlock-throwaway:test
podman rmi hello-world
```

Note: while recording this session, removing the temporary directory was blocked by the harness running the
commands. In a normal shell, it’s safe to remove:

```bash
rm -rf "$tmp"
```

## Follow-ups (likely fixes if you want “normal” images to work)

- Configure subordinate IDs (`/etc/subuid`, `/etc/subgid`) so rootless Podman has a real UID/GID range.
  - The error messages suggested running `podman system migrate` after fixing mappings.
- Ensure `/dev/net/tun` exists if you want rootless networking (slirp4netns) to work.
  - If you can’t get TUN, `--network none` (or another network strategy) may be required.
