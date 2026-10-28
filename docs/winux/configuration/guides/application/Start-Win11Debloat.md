# Start-Win11Debloat

Runs the vendored Win11Debloat script from the local repository to remove bloatware, disable telemetry, and apply system tweaks.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BootstrapConfig.LocalScripts.Win11Debloat`](../../configuration-reference.md#bootstrapconfig) | string (path) | `{RepoRoot}\Windows\Win11Debloat\vendor\Win11Debloat.ps1` | The vendored script to run. `{RepoRoot}` is expanded; empty falls back to the same default path. A missing script is reported and the step skipped. |
| [`PathTemplates.Projects.Self.Root`](../../configuration-reference.md#path-templates--placeholder-system) | path template | `{RepoRoot}` | The repository root used for `{RepoRoot}`, the fallback script path and the saved-settings file `Windows\Win11Debloat\LastUsedSettings.json` (read from `$global:MachineSpecificPaths.Projects.Self.Root`). |
| [`BootstrapConfig.Steps.Win11Debloat`](../../configuration-reference.md#bootstrapconfig) | boolean or per-machine-type hashtable | `$false` (built-in default) | Whether `Bootstrap -WithInitialSetup` runs this function. |

The saved settings are not a configuration key: they are the repository file `Windows\Win11Debloat\LastUsedSettings.json`, which the function links into the vendored script's `Config` folder when it exists and is non-empty.

## Decisions

1. Should a first-time `Bootstrap -WithInitialSetup` debloat this machine?
    - Options: `$true`, `$false`, or a per-machine-type hashtable with a `Default` fallback under `BootstrapConfig.Steps.Win11Debloat`. Running `Start-Win11Debloat` by hand works either way.
    - Default: `$false` - a vanilla bootstrap never runs or prompts for it.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)
2. Is the vendored script somewhere other than `Windows\Win11Debloat\vendor`?
    - Options: A full path, `{RepoRoot}` allowed, under `BootstrapConfig.LocalScripts.Win11Debloat`.
    - Default: The shipped vendored path. Almost nobody changes this.
    - More detail: [`BootstrapConfig`](../../configuration-reference.md#bootstrapconfig)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `BootstrapConfig`
2. Reload and confirm the merge landed

## Step 1: Set `BootstrapConfig`

Opt the Bootstrap step in, and move the script only if you vendor it elsewhere. Hashtables deep-merge, so set only the keys you change.

```powershell
BootstrapConfig = @{
    Steps        = @{
        Win11Debloat = $true
    }
    LocalScripts = @{
        Win11Debloat = "{RepoRoot}\Windows\Win11Debloat\vendor\Win11Debloat.ps1"
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.BootstrapConfig.LocalScripts.Win11Debloat
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Resolve-BootstrapSteps | Where-Object Name -eq "Win11Debloat"
Test-Path ($global:Configuration.BootstrapConfig.LocalScripts.Win11Debloat -replace '\{RepoRoot\}', $global:MachineSpecificPaths.Projects.Self.Root)
Test-Path (Join-Path $global:MachineSpecificPaths.Projects.Self.Root "Windows\Win11Debloat\LastUsedSettings.json")
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    BootstrapConfig = @{
        Steps        = @{
            Win11Debloat = $true
        }
        LocalScripts = @{
            Win11Debloat = "{RepoRoot}\Windows\Win11Debloat\vendor\Win11Debloat.ps1"
        }
    }
}
```

## Related

- [`Start-Win11Debloat` in the Application module reference](../../../modules/application.md#start-win11debloat) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Update-Win11DebloatVendor`](Update-Win11DebloatVendor.md) - refreshes the vendored script this function runs
- [`Bootstrap`](../bootstrap/Bootstrap.md) - runs this function when `BootstrapConfig.Steps.Win11Debloat` is on
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
