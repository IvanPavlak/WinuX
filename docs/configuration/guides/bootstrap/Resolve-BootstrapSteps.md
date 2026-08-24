# Resolve-BootstrapSteps

Resolves which Bootstrap provisioning steps should run, in a single pass.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig) | hashtable, 9 keys | hashtable, 9 keys | Everything about how `Bootstrap` runs: the `Steps` toggles that decide which provisioning steps execute, `DataFiles` (relative paths to the three app-list CSVs), `LocalScripts` / `ExternalScripts`, `PersonalSteps`, `RepositoryUpdateScope`, `DefaultBranch`, and where the bootstrap log lands. |

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

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `BootstrapConfig`
2. Reload and confirm the merge landed

## Step 1: Set `BootstrapConfig`

Everything about how `Bootstrap` runs: the `Steps` toggles that decide which provisioning steps execute, `DataFiles` (relative paths to the three app-list CSVs), `LocalScripts` / `ExternalScripts`, `PersonalSteps`, `RepositoryUpdateScope`, `DefaultBranch`, and where the bootstrap log lands.

```powershell
BootstrapConfig = @{
    Steps = @{
        CoreAiRules = $true
    }
}
```

## Step 2: Reload and confirm the merge landed

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
Resolve-BootstrapSteps | Format-Table
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
}
```

## Related

- [`Resolve-BootstrapSteps` in the Bootstrap module reference](../../../modules/bootstrap.md#resolve-bootstrapsteps) - parameters, usage and behaviour
- [Bootstrap configuration guides](README.md) - every guide for this module
- [Add New Machine](add-new-machine.md) - the full 7-step walk for bringing a new machine type online
- [`Create-CondaEnvironments`](../application/Create-CondaEnvironments.md) - reads the same configuration
- [`Start-Win11Debloat`](../application/Start-Win11Debloat.md) - reads the same configuration
- [`Update-Win11DebloatVendor`](../application/Update-Win11DebloatVendor.md) - reads the same configuration
- [`Bootstrap`](Bootstrap.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
