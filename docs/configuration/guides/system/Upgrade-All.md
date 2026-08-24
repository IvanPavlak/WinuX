# Upgrade-All

Upgrades all packages across the package managers WinuX actually uses on this machine, resolved by `Resolve-PackageManagers`: listed in `PackageManagers` in `Configuration.psd1` **and** holding at least one app for this machine type.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Upgrade-All
Upgrade-All -PackageManager "WinGet"
Upgrade-All -PackageManager "WinGet", "Scoop"
```

## Related

- [`Upgrade-All` in the System module reference](../../../modules/system.md#upgrade-all) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
