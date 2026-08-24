# Import-AppCsv

The single read path for the three app lists.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BootstrapConfig.DataFiles`](../../configuration-reference.md#bootstrapconfig) | hashtable of list name to repository-relative path | 4 entries | Where the three committed app-list CSVs live, relative to the repository root. `Import-AppCsv` resolves the path from here, which is what keeps the location configuration-driven. |
| [`PathTemplates.Projects.Self`](../../configuration-reference.md#path-templates--placeholder-system) | hashtable, path fields | shipped | WinuX own checkout: `Root` (the repository root) and `VSCodeWorkspaces` (where `.code-workspace` files live). Expanded into `$global:MachineSpecificPaths.Projects.Self`. |

This is the single read path for all three app lists, and the place the overlay rules live. An overlay row whose `App` matches a base row **replaces** it (so an overlay can pin a version, change the install scope, or re-target a machine without editing a tracked file). A row with a new `App` is **added**. A row whose `App` is `-` **removes** the base row - without that there would be no way to opt out of a shipped app. Comment rows (`App` starting with `#`) and blank `App` cells are dropped from both files. Row order is base-first, then overlay-only additions.

## Decisions

1. Do you need to move an app-list CSV?
    - Options: Repository-relative path per list name.
    - Default: The shipped paths under `Windows/PowerShell/Modules/Bootstrap/Data/`.
    - More detail: [`BootstrapConfig.DataFiles`](../../configuration-reference.md#bootstrapconfig)
2. Is the WinuX checkout in the standard place?
    - Options: A path, normally `{Dev}\WinuX` or `{Dev}\Dotfiles`. `{RepoRoot}` already resolves the running repository, so this rarely needs changing.
    - Default: The shipped template.
    - More detail: [`PathTemplates.Projects.Self`](../../configuration-reference.md#path-templates--placeholder-system)
3. Where do your `.code-workspace` files live?
    - Options: A directory path under `Projects.Self.VSCodeWorkspaces`.
    - Default: The shipped template.
    - More detail: [`PathTemplates.Projects.Self`](../../configuration-reference.md#path-templates--placeholder-system)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `BootstrapConfig.DataFiles`
2. Set `PathTemplates.Projects.Self`
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

## Step 2: Set `PathTemplates.Projects.Self`

WinuX own checkout: `Root` (the repository root) and `VSCodeWorkspaces` (where `.code-workspace` files live). Expanded into `$global:MachineSpecificPaths.Projects.Self`.

```powershell
PathTemplates = @{
    Projects = @{
        Self = @{
            Root             = "{RepoRoot}"
            VSCodeWorkspaces = "{RepoRoot}\VSCode\Workspaces"
        }
    }
}
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
$global:Configuration.PathTemplates
Import-AppCsv -DataFileKey WinGetApps | Measure-Object
Import-AppCsv -DataFileKey ScoopApps | Select-Object -First 5
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
    PathTemplates = @{
        Projects = @{
            Self = @{
                Root             = "{RepoRoot}"
                VSCodeWorkspaces = "{RepoRoot}\VSCode\Workspaces"
            }
        }
    }
}
```

## Related

- [`Import-AppCsv` in the Bootstrap module reference](../../../modules/bootstrap.md#import-appcsv) - parameters, usage and behaviour
- [Bootstrap configuration guides](README.md) - every guide for this module
- [Add New Machine](add-new-machine.md) - the full 7-step walk for bringing a new machine type online
- [`Install-ChocolateyApps`](../application/Install-ChocolateyApps.md) - reads the same configuration
- [`Install-ScoopApps`](../application/Install-ScoopApps.md) - reads the same configuration
- [`Install-WingetApps`](../application/Install-WingetApps.md) - reads the same configuration
- [`Get-PinnedApps`](../system/Get-PinnedApps.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
