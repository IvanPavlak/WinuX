# Merge-LayoutProjectOverrides

Applies a layout file's `ProjectOverrides` block - project variants of one workspace's layout - for the project(s) a workspace is opened with, and validates every variant.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`ProjectActions`](../../configuration-reference.md#project-actions) | ordered list of single-key hashtables | ordered list | The valid project tokens. A `ProjectOverrides` key token that is not a `ProjectActions` name is an error, and its variant is not applied. |
| [`ZoneNameMappings`](../../configuration-reference.md#layout-numbers--zone-mappings) | hashtable of layout name to zone names | one entry per shipped layout | The zones each FancyZones layout has. An override entry whose `Zone` is missing from the layout its desktop and monitor end up with is an error. Zones are not checked when it is empty. |
| [`ProjectOverrides`](../../configuration-reference.md#workspace-layouts) (layout file) | hashtable of project scope to `@{ Monitors; Layout }` | none | Lives at the end of a `<Workspace>_<MachineType>.psd1` layout file. `Monitors` merges key by key; the override's `Layout` entries replace every base entry on the same desktop and monitor and are added for a pair the base does not use. |

## Decisions

1. Which projects need a layout of their own, and which desktops differ?
    - Options: One `ProjectOverrides` key per project, or one key for several (`"MyProject/OtherProject"`). Each variant lists only the desktop-and-monitor pairs that differ, with the complete set of entries for each pair. Clearing a pair without replacement is not supported.
    - Default: No `ProjectOverrides` - every project gets the base layout.
    - More detail: [`ProjectOverrides`](../../configuration-reference.md#workspace-layouts)
2. Is every project token a `ProjectActions` name?
    - Options: Use the names exactly as `ProjectActions` lists them (case-insensitive). A typo is reported on every open, selected or not, and that variant is never applied.
    - Default: Whatever `ProjectActions` holds.
    - More detail: [`ProjectActions`](../../configuration-reference.md#project-actions)
3. Does a variant change a desktop's zone layout?
    - Options: Add `Monitors = @{ <Monitor> = @{ VirtualDesktopLayouts = @{ <desktop> = "<layout>" } } }` to the variant when its entries use zones the base zone layout does not have (`Left` and `Right` on a desktop the base keeps fullscreen). The zone check uses that variant's layout.
    - Default: The base `Monitors` section.
    - More detail: [`ZoneNameMappings`](../../configuration-reference.md#layout-numbers--zone-mappings)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

The exception on this page is `ProjectOverrides` itself: it is not a configuration key and goes at the end of the workspace's layout file under `Windows/PowerShell/Modules/Window/Layouts/<MachineType>/`.

## Steps Overview

1. Make sure the projects exist in `ProjectActions`
2. Add the `ProjectOverrides` block to the layout file
3. Reload and confirm the merge landed

## Step 1: Make sure the projects exist in `ProjectActions`

The tokens of a `ProjectOverrides` key are `ProjectActions` names.

```powershell
ProjectActions = @(
    @{ MyProject = @( @{ Action = "Open-VSCode"; Parameters = @{ Folder = "MyProject" } } ) }
    @{ OtherProject = @( @{ Action = "Open-VSCode"; Parameters = @{ Folder = "OtherProject" } } ) }
)
```

## Step 2: Add the `ProjectOverrides` block to the layout file

After the `Layout` array of `Layouts/PC/Client_PC.psd1`. Anchor VS Code titles on the folder name as VS Code ends its caption, so `MyProject` does not also match `MyProjectApi`.

```powershell
ProjectOverrides = @{
    "MyProject" = @{
        Monitors = @{ Primary = @{ VirtualDesktopLayouts = @{ 2 = "One" } } }
        Layout   = @(
            @{ ProcessName = "Code"; WindowTitle = "MyProject - Visual Studio Code$"; DesktopNumber = 2; Monitor = "Primary"; Zone = "Left" }
            @{ ProcessName = "Code"; WindowTitle = "MyProjectApi - Visual Studio Code$"; DesktopNumber = 2; Monitor = "Primary"; Zone = "Right" }
        )
    }
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
Get-OrderedNames $global:Configuration.ProjectActions
```

## Verification

Read-only checks. None of these change anything.

```powershell
$layout = Import-PowerShellDataFile "<RepoRoot>\Windows\PowerShell\Modules\Window\Layouts\PC\Client_PC.psd1"
$merged = Merge-LayoutProjectOverrides -Config $layout -Project MyProject
$merged.Applied
$merged.Errors
$merged.Config.Layout | Where-Object DesktopNumber -eq 2
Visualize-Layouts -Layout Client_PC
```

`Applied` names the variants used, `Errors` every problem (also reported by `Validate-Layout` and at the start of every open of the workspace), and `Visualize-Layouts` draws a `PROJECT VARIANT [MyProject]` drawing next to the base layout.

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    ProjectActions = @(
        @{ MyProject = @( @{ Action = "Open-VSCode"; Parameters = @{ Folder = "MyProject" } } ) }
        @{ OtherProject = @( @{ Action = "Open-VSCode"; Parameters = @{ Folder = "OtherProject" } } ) }
    )
    ZoneNameMappings = @{
        One  = @{ Left = 0; Right = 1 }
        Zero = @{ Fullscreen = 0 }
    }
    # ProjectOverrides is not a Configuration.local.psd1 key - it goes at the end of Layouts/<MachineType>/<Workspace>_<MachineType>.psd1 (Step 2)
}
```

## Related

- [`Merge-LayoutProjectOverrides` in the Window module reference](../../../modules/window.md#merge-layoutprojectoverrides) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
- [`Set-WorkspaceWindowLayout`](Set-WorkspaceWindowLayout.md) - applies the variant with `-Project`
- [Configure Window Layout](configure-window-layout.md) - the 3-layer layout system, zones and visualization
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
