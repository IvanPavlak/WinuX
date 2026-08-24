# Install-ChocolateyApps

Installs Chocolatey-managed apps from the WinuX CSV, filtered by machine type.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BootstrapConfig.DataFiles`](../../configuration-reference.md#bootstrapconfig) | hashtable of list name to repository-relative path | 4 entries | Where the three committed app-list CSVs live, relative to the repository root. `Import-AppCsv` resolves the path from here, which is what keeps the location configuration-driven. |
| [`PackageManagers`](../../configuration-reference.md#packagemanagers) | array of manager names | `@("WinGet")` | Which package managers Bootstrap provisions and installs from. `Resolve-PackageManagers` filters the list by machine type. |

App lists are not `Configuration.psd1` keys. The committed CSV named by `BootstrapConfig.DataFiles` is upstream's baseline and stays untouched; everything you choose for this machine goes in the sibling `<name>.local.csv` overlay, which `Import-AppCsv` layers on top at read time. `Save-AppCsvOverlay` writes it for you.

## Decisions

1. Do you need to move an app-list CSV?
    - Options: Repository-relative path per list name.
    - Default: The shipped paths under `Windows/PowerShell/Modules/Bootstrap/Data/`.
    - More detail: [`BootstrapConfig.DataFiles`](../../configuration-reference.md#bootstrapconfig)
2. Which package managers do you want on this machine?
    - Options: Any of `WinGet`, `Scoop`, `Chocolatey`. The array replaces wholesale, so list all of them you want.
    - Default: `@("WinGet")`.
    - More detail: [`PackageManagers`](../../configuration-reference.md#packagemanagers)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `PackageManagers` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `BootstrapConfig.DataFiles`
2. Set `PackageManagers`
3. Reload and confirm the merge landed

## Step 1: Set `BootstrapConfig.DataFiles`

Where the three committed app-list CSVs live, relative to the repository root. `Import-AppCsv` resolves the path from here, which is what keeps the location configuration-driven.

```powershell
BootstrapConfig = @{
    DataFiles = @{
        WinGetApps = "Windows/PowerShell/Modules/Bootstrap/Data/WinGetApps.csv"
    }
}
```

## Step 2: Set `PackageManagers`

Which package managers Bootstrap provisions and installs from. `Resolve-PackageManagers` filters the list by machine type.

```powershell
PackageManagers = @("WinGet", "Scoop")
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.BootstrapConfig
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.BootstrapConfig
$global:Configuration.PackageManagers
Import-AppCsv -DataFileKey ChocolateyApps | Select-Object App, Machine -First 20
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    BootstrapConfig = @{
        DataFiles = @{
            WinGetApps = "Windows/PowerShell/Modules/Bootstrap/Data/WinGetApps.csv"
        }
    }
    PackageManagers = @("WinGet", "Scoop")
}
```

## Related

- [`Install-ChocolateyApps` in the Application module reference](../../../modules/application.md#install-chocolateyapps) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [Add Browser Group](add-browser-group.md) - browser groups, nesting, unique names, search and per-browser selection
- [`Install-ScoopApps`](Install-ScoopApps.md) - reads the same configuration
- [`Install-WingetApps`](Install-WingetApps.md) - reads the same configuration
- [`Import-AppCsv`](../bootstrap/Import-AppCsv.md) - reads the same configuration
- [`Get-PinnedApps`](../system/Get-PinnedApps.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
