# Sync-Win11DebloatSettings

Links Win11Debloat's saved settings to the repository file and adopts settings saved outside it.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PathTemplates.Projects.Self.Root`](../../configuration-reference.md#path-templates--placeholder-system) | path template | `{RepoRoot}` | The repository root the saved-settings file `Windows\Win11Debloat\LastUsedSettings.json` is found under (read from `$global:MachineSpecificPaths.Projects.Self.Root`). The other end of the link, `%LOCALAPPDATA%\Win11Debloat\LastUsedSettings.json`, is where the vendored script keeps its settings and is not configurable. |

## Decisions

1. Is the WinuX checkout somewhere other than the running repository?
    - Options: A path; `{RepoRoot}` already resolves the running repository, so this rarely needs changing.
    - Default: `{RepoRoot}`.
    - More detail: [`PathTemplates`](../../configuration-reference.md#path-templates--placeholder-system)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `PathTemplates.Projects.Self.Root`
2. Reload and confirm the merge landed

## Step 1: Set `PathTemplates.Projects.Self.Root`

The repository root. Hashtables deep-merge, so setting only this key keeps the other `Projects.Self` paths.

```powershell
PathTemplates = @{
    Projects = @{
        Self = @{
            Root = "{RepoRoot}"
        }
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:MachineSpecificPaths.Projects.Self.Root
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Test-Path (Join-Path $global:MachineSpecificPaths.Projects.Self.Root "Windows\Win11Debloat\LastUsedSettings.json")
(Get-Item (Join-Path $env:LOCALAPPDATA "Win11Debloat\LastUsedSettings.json") -ErrorAction SilentlyContinue).Target
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PathTemplates = @{
        Projects = @{
            Self = @{
                Root = "{RepoRoot}"
            }
        }
    }
}
```

## Related

- [`Sync-Win11DebloatSettings` in the Application module reference](../../../modules/application.md#sync-win11debloatsettings) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Start-Win11Debloat`](Start-Win11Debloat.md) - calls this function before its menu and after an interactive run
- [`Update-Win11DebloatVendor`](Update-Win11DebloatVendor.md) - reads the same `Projects.Self.Root`
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
