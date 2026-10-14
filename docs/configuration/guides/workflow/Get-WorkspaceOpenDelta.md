# Get-WorkspaceOpenDelta

The ownership rule for `Close-Workspace`, in one place.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal`](../../configuration-reference.md#universal-constants) | hashtable, 27 keys | hashtable, 27 keys | Machine-independent constants. This function reads only `Universal.VisibleWindowExclusions` (array of process names, 7 shipped), and only with `-AdoptUnclaimed`: a window that was already on screen is never adopted when its process is named there (nor when it is one of the shell hosts `Get-ShellProcessName` lists), and `WindowsTerminal` on the list keeps pre-existing terminal tabs out too. Windows and tabs the open created are recorded regardless. |

## Decisions

1. Which already-running applications should a plain `Open-Workspace` never take ownership of?
    - Options: Process names (no `.exe`) in `Universal.VisibleWindowExclusions`, matched exactly and case-insensitively. The same list is what `Kill-All` never force-kills, so an entry affects both. Keep `WindowsTerminal` and the PowerToys entries.
    - Default: The shipped seven: `Rainmeter`, `WindowsTerminal`, `Docker Desktop`, `obs64`, `PowerToys`, `PowerToys.FancyZones`, `PowerToys.Settings`.
    - More detail: [`Universal`](../../configuration-reference.md#universal-constants)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `Universal.VisibleWindowExclusions` - `Universal` itself deep-merges, but that key is an array, so whatever you write is the complete list.

## Steps Overview

1. Set `Universal`
2. Reload and confirm the merge landed

## Step 1: Set `Universal`

The processes a plain open never adopts. Copy the shipped list and add to it.

```powershell
Universal = @{
    VisibleWindowExclusions = @(
        "Rainmeter"
        "WindowsTerminal"
        "Docker Desktop"
        "obs64"
        "PowerToys"
        "PowerToys.FancyZones"
        "PowerToys.Settings"
        "MyTrayApp"
    )
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal
$global:Configuration.Universal.VisibleWindowExclusions
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal = @{
        VisibleWindowExclusions = @(
            "Rainmeter"
            "WindowsTerminal"
            "Docker Desktop"
            "obs64"
            "PowerToys"
            "PowerToys.FancyZones"
            "PowerToys.Settings"
            "MyTrayApp"
        )
    }
}
```

## Related

- [`Get-WorkspaceOpenDelta` in the Workflow module reference](../../../modules/workflow.md#get-workspaceopendelta) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [`Terminate-AllProcessesWithVisibleWindows`](../system/Terminate-AllProcessesWithVisibleWindows.md) - reads the same `VisibleWindowExclusions` list
- [`Open-Browser`](../application/Open-Browser.md) - reads the same configuration
- [`Open-LeagueOfLegends`](../application/Open-LeagueOfLegends.md) - reads the same configuration
- [`Open-NotepadPlusPlus`](../application/Open-NotepadPlusPlus.md) - reads the same configuration
- [`Open-Steam`](../application/Open-Steam.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
