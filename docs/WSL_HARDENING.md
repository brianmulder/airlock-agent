# WSL Hardening

Goal: prevent accidental access to Windows drives while allowing a narrow Dropbox context mount.

## 1) Disable Windows drive automount

Required: edit `/etc/wsl.conf`:

```ini
[automount]
enabled = false
mountFsTab = true

# Optional: reduce Windows interop
[interop]
enabled = false
appendWindowsPath = false
```

Required: apply changes:

```powershell
wsl --shutdown
```

## 2) Mount only the context subfolder

Required: edit `/etc/fstab` (replace `YourWinUser` and the subfolder name):

```text
# <Source>                                   <Target>                <Type>  <Options>
C:\Users\YourWinUser\Dropbox\fred            /home/youruser/dropbox/fred  drvfs   defaults,uid=1000,gid=1000,metadata 0 0
```

Required: apply:

```powershell
wsl --shutdown
```

## 3) Verify

Required: verify from WSL:

```bash
ls /mnt/c   # should fail or be absent if automount is disabled
ls ~/dropbox/fred  # should list your context folder
```

## 4) Rollback

- Re-enable automount by removing or updating `/etc/wsl.conf` and running `wsl --shutdown`.
- Remove the `/etc/fstab` entry if you no longer want the context mounted.
