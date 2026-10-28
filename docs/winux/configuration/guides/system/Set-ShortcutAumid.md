# Set-ShortcutAumid

Creates or updates a `.lnk` shortcut and stamps an explicit AppUserModelID (the `System.AppUserModel.ID` shell property) on it.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Set-ShortcutAumid -LinkPath <path.lnk> -TargetPath <path.exe> -Aumid <id>
Set-ShortcutAumid -LinkPath <existing.lnk> -Aumid <id>
```

## Related

- [`Set-ShortcutAumid` in the System module reference](../../../modules/system.md#set-shortcutaumid) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
