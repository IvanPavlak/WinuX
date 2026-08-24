# Save-AppCsvOverlay

Writes the machine-local app list overlay, validating before it replaces anything.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).
>
> Direction: **writes** configuration. This function edits `Configuration.psd1` in place rather than reading it, so the "Where to Put Values" section below describes what it produces, not what you type by hand.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig) | hashtable, 9 keys | hashtable, 9 keys | Everything about how `Bootstrap` runs: the `Steps` toggles that decide which provisioning steps execute, `DataFiles` (relative paths to the three app-list CSVs), `LocalScripts` / `ExternalScripts`, `PersonalSteps`, `RepositoryUpdateScope`, `DefaultBranch`, and where the bootstrap log lands. |
| [`ValidMachineTypes`](../../configuration-reference.md#valid-machine-types) | array of strings | `@("Test")` | The machine types WinuX accepts. `DetermineMachineType` refuses anything not listed, and `Test-MachineTypeScope` uses it to decide whether a CSV row or a step applies. |

This is the writer for the `*.local.csv` overlays. It never modifies the committed CSV - it writes the sibling overlay that `Import-AppCsv` layers on top, and leaves a `.bak` copy beside it.

## Decisions

1. Which bootstrap steps should run on this machine?
    - Options: Each entry under `BootstrapConfig.Steps` is either a boolean or a per-machine-type hashtable with a `Default` fallback. Steps that act the moment they run (`CoreAiRules`, taskbar, wallpaper) ship off.
    - Default: The shipped `Steps` map. Change only the steps you actually want to flip.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)
2. Do you need to change where the app-list CSVs live?
    - Options: Repository-relative paths under `BootstrapConfig.DataFiles`, keyed `WinGetApps`, `ScoopApps`, `ChocolateyApps`.
    - Default: The shipped paths. Almost nobody changes these.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)
3. Where should the bootstrap log be written?
    - Options: `LogFileLocation` (for example `Desktop`) plus `LogFilePrefix`.
    - Default: `Desktop` with prefix `BootstrapLog`.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)
4. Which machine types do you use?
    - Options: One name per type, e.g. `@("Test", "Machine", "Laptop", "Work")` - see [Add New Machine](../bootstrap/add-new-machine.md). The array replaces wholesale, so keep `Test` in the list unless you really mean to drop it.
    - Default: `@("Test")`.
    - More detail: [`ValidMachineTypes`](../../configuration-reference.md#valid-machine-types)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ValidMachineTypes` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `BootstrapConfig`
2. Set `ValidMachineTypes`
3. Reload and confirm the merge landed

## Step 1: Set `BootstrapConfig`

Everything about how `Bootstrap` runs: the `Steps` toggles that decide which provisioning steps execute, `DataFiles` (relative paths to the three app-list CSVs), `LocalScripts` / `ExternalScripts`, `PersonalSteps`, `RepositoryUpdateScope`, `DefaultBranch`, and where the bootstrap log lands.

```powershell
BootstrapConfig = @{
    Steps = @{
        CoreAiRules = $true
    }
}
```

## Step 2: Set `ValidMachineTypes`

The machine types WinuX accepts. `DetermineMachineType` refuses anything not listed, and `Test-MachineTypeScope` uses it to decide whether a CSV row or a step applies.

```powershell
ValidMachineTypes = @("Test", "Machine", "Laptop")
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
$global:Configuration.ValidMachineTypes
Import-AppCsv -DataFileKey WinGetApps | Select-Object -First 10
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    BootstrapConfig = @{
        Steps = @{
            CoreAiRules = $true
        }
    }
    ValidMachineTypes = @("Test", "Machine", "Laptop")
}
```

## Related

- [`Save-AppCsvOverlay` in the Configuration module reference](../../../modules/configuration.md#save-appcsvoverlay) - parameters, usage and behaviour
- [Configuration configuration guides](README.md) - every guide for this module
- [`Create-CondaEnvironments`](../application/Create-CondaEnvironments.md) - reads the same configuration
- [`Start-Win11Debloat`](../application/Start-Win11Debloat.md) - reads the same configuration
- [`Update-Win11DebloatVendor`](../application/Update-Win11DebloatVendor.md) - reads the same configuration
- [`Bootstrap`](../bootstrap/Bootstrap.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
