# New-WSLSymbolicLink

Creates a single symlink inside a WSL distribution (`ln -s`) at `Path` pointing to `Target`, backing up whatever it replaces.

A real file already sitting at `Path` is copied out to `<Repo>\Backups\SymbolicLinks\<DisplayName>\<timestamp>\` on the Windows side before it is removed, which matters most for files that only ever existed inside the distro (a shell profile, an SSH config) and so have no Windows copy to fall back on. That folder is gitignored, so the copies are easy to find and never committed. If the backup cannot be written the link is skipped and the existing item is left untouched. An existing symlink is replaced without a backup. `-BackupRoot` takes a Windows path and is translated into the distribution with `wslpath`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
New-WSLSymbolicLink -Path "/home/user/.ssh/config" -Target "/mnt/c/Users/User/.ssh/config" -Distribution "Ubuntu"
```

## Related

- [`New-WSLSymbolicLink` in the System module reference](../../../modules/system.md#new-wslsymboliclink) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
