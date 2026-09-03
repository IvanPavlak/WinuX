# Set-WorkspaceWindowLayout

Loads and applies a predefined, machine-specific window layout for a workspace.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`SimpleLayoutWorkspaces`](../../configuration-reference.md#workspace-layouts) | array of workspace names | `@("Fullscreen", "Empty")` | Workspaces that use a single simple layout instead of a per-machine `<Workspace>_<MachineType>.psd1` file. `Set-WorkspaceWindowLayout` and `Add-WindowLayout` both consult it. |
| [`LayoutMachineTypeOverrides`](../../configuration-reference.md#layout-set-overrides) | hashtable of machine type to layout set name | `@{ Test = "" }` | Lets a machine use another machine layout set - for example a laptop docked to a different monitor arrangement. `Get-LayoutMachineType` resolves it, so layouts and the reset target can never disagree. An override name is not a machine type: it needs no `ValidMachineTypes` entry and no base paths, only `<Workspace>_<Name>.psd1` layout files. |
| [`WorkspaceLayoutPipelining`](../../configuration-reference.md#layout-numbers--zone-mappings) | bool | `$true` | Whether each virtual desktop is positioned and snapped as soon as every window on it is stable, while the slower windows on other desktops still load. `$false` restores the strictly sequential wait, then position, then snap order. |

## Decisions

1. Which workspaces need only a simple layout?
    - Options: One name per workspace. The array replaces wholesale.
    - Default: `Fullscreen` and `Empty`.
    - More detail: [`SimpleLayoutWorkspaces`](../../configuration-reference.md#workspace-layouts)
2. Should this machine use another machine layout files?
    - Options: Machine type to override name. Empty means use the machine own type.
    - Default: Empty - no override.
    - More detail: [`LayoutMachineTypeOverrides`](../../configuration-reference.md#layout-set-overrides)
3. Should desktops be positioned and snapped as they become ready?
    - Options: `$true` pipelines each desktop into the wait phase; `$false` waits for the slowest window first.
    - Default: `$true`. Switch it off to compare the two orders with `Get-WorkspaceBenchmark`, or if a layout misbehaves only with pipelining on.
    - More detail: [`WorkspaceLayoutPipelining`](../../configuration-reference.md#layout-numbers--zone-mappings)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `SimpleLayoutWorkspaces` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `SimpleLayoutWorkspaces`
2. Set `LayoutMachineTypeOverrides`
3. Set `WorkspaceLayoutPipelining`
4. Reload and confirm the merge landed

## Step 1: Set `SimpleLayoutWorkspaces`

Workspaces that use a single simple layout instead of a per-machine `<Workspace>_<MachineType>.psd1` file. `Set-WorkspaceWindowLayout` and `Add-WindowLayout` both consult it.

```powershell
SimpleLayoutWorkspaces = @("Fullscreen", "Empty", "MyScratch")
```

## Step 2: Set `LayoutMachineTypeOverrides`

Lets a machine use another machine layout set - for example a laptop docked to a different monitor arrangement. `Get-LayoutMachineType` resolves it, so layouts and the reset target can never disagree. An override name is not a machine type: it needs no `ValidMachineTypes` entry and no base paths, only `<Workspace>_<Name>.psd1` layout files.

```powershell
LayoutMachineTypeOverrides = @{
    Test = "Docked"
}
```

## Step 3: Set `WorkspaceLayoutPipelining`

Whether `Set-WorkspaceWindowLayout` positions and snaps each virtual desktop as soon as every window on it is stable, while the slower windows on other desktops are still loading. The shipped default is `$true`; set `$false` for the strictly sequential order.

```powershell
WorkspaceLayoutPipelining = $false
```

## Step 4: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.SimpleLayoutWorkspaces
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.SimpleLayoutWorkspaces
$global:Configuration.LayoutMachineTypeOverrides
Get-LayoutMachineType
Visualize-Layouts
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    SimpleLayoutWorkspaces = @("Fullscreen", "Empty", "MyScratch")
    LayoutMachineTypeOverrides = @{
        Test = "Docked"
    }
}
```

## Related

- [`Set-WorkspaceWindowLayout` in the Window module reference](../../../modules/window.md#set-workspacewindowlayout) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
- [Configure Window Layout](configure-window-layout.md) - the 3-layer layout system, zones and visualization
- [`Add-WindowLayout`](../configuration/Add-WindowLayout.md) - reads the same configuration
- [`Get-LayoutMachineType`](Get-LayoutMachineType.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
