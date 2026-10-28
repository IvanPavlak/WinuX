# Upgrade-All

Upgrades all packages across the package managers WinuX actually uses on this machine, resolved by `Resolve-PackageManagers`: listed in `PackageManagers` in `Configuration.psd1` **and** holding at least one app for this machine type.

> [!NOTE]
> Bootstrap does **not** run this by default. `BootstrapConfig.Steps.UpgradeAll` ships `$false`, because the bulk upgrade this function performs (`winget upgrade --all`, `scoop update *`, `choco upgrade all -y`) touches every package the manager knows about on the machine, not only the ones WinuX installs. Opt in via [`Resolve-BootstrapSteps`](../bootstrap/Resolve-BootstrapSteps.md), or run the function directly.

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
