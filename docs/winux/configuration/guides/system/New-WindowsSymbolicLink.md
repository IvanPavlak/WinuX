# New-WindowsSymbolicLink

Creates a single native Windows symbolic link at `Path` pointing to `Target`, backing up whatever it replaces.

A real file or directory already sitting at `Path` is copied into `<Repo>\Backups\Windows\SymbolicLinks\<DisplayName>\<timestamp>\` (via [`Backup-RepositoryItem`](../helper/Backup-RepositoryItem.md)) before it is removed, so linking over a hand-written PowerShell profile or an existing PowerToys settings file never loses it. That folder is gitignored, so the copies are easy to find and never committed. If the backup cannot be written the link is skipped and the existing item is left untouched. An existing symlink is replaced without a backup, since it carries no content of its own. Use `-BackupRoot` to archive somewhere other than the repository's sink.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
New-WindowsSymbolicLink -Path "$env:USERPROFILE\.gitconfig" -Target "C:\Repo\Git\.gitconfig"
```

## Related

- [`New-WindowsSymbolicLink` in the System module reference](../../../modules/system.md#new-windowssymboliclink) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
