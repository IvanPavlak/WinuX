# Enable-DeveloperMode

Enables Windows Developer Mode by setting the registry value `AllowDevelopmentWithoutDevLicense` to `1` under `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Enable-DeveloperMode
```

## Related

- [`Enable-DeveloperMode` in the System module reference](../../../modules/system.md#enable-developermode) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
