# Get-WinGetPinnedIds

Returns which of the given WinGet app IDs winget currently has a pin for, in one `winget pin list` call.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-WinGetPinnedIds -AppId "Git.Git", "Microsoft.PowerToys"
```

## Related

- [`Get-WinGetPinnedIds` in the System module reference](../../../modules/system.md#get-wingetpinnedids) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
