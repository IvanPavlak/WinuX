# Get-InstalledApps

Enumerates all installed Windows applications (both 64-bit and 32-bit) by scanning the registry's Uninstall keys, then exports the results to `installed_apps.txt` on the Desktop.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-InstalledApps
```

## Related

- [`Get-InstalledApps` in the System module reference](../../../modules/system.md#get-installedapps) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
