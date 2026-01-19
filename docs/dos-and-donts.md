# Dos and Don’ts (Using `yolo` Safely)

This is a short, practical checklist for daily use. It’s meant to keep host access explicit and reduce the
chance of accidental credential exposure.

## Do

- Keep your workspace and any extra writable mounts on a local Linux filesystem.
- Use `yolo --mount-ro …` for inputs and `yolo --add-dir …` to add explicit writable directories.
- Review outputs on the host before copying anything into your repo.
- Publish only the ports you need (`yolo --publish …`) and keep `AIRLOCK_NETWORK=host` as an exception.
- Disable the container engine socket mount when you don’t need it:

```bash
AIRLOCK_MOUNT_ENGINE_SOCKET=0 yolo
```

- Treat Docker-in-Docker (`yolo --dind`) as an exception: it runs the agent container privileged.

## Don’t

- Don’t mount broad host paths (especially `$HOME`) into `yolo` containers.
- Don’t mount credential directories unless you truly need them (examples: `~/.ssh`, `~/.aws`, `~/.kube`,
  `~/.gnupg`, password manager sockets).
- Don’t keep secrets in the repo working tree (e.g., `.env` files, cloud keys). If they’re in the workspace,
  the agent can read them.
- Don’t assume “container = safe”; treat the agent container as a high-trust execution environment for the
  code it runs.

## Notes (Multiple Agents)

- Codex: state is in `~/.codex/` (mounted into `yolo` by default).
- OpenCode: state is in `~/.config/opencode/` and `~/.local/share/opencode/` (mounted by default; opt out via
  `AIRLOCK_MOUNT_OPENCODE=0`).
- Other agent CLIs: prefer mounting only their specific state directories rather than broad host locations.
