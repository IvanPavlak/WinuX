# Resolve-WorkspaceActions

Decides which of a workspace's configured actions run on this machine: the ones whose `Machine` scope covers the detected machine type and whose `LayoutMachine` scope covers the layout set the window layout will be read from.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`WorkspaceActions`](../../configuration-reference.md#workspace-actions) | hashtable of workspace name to action array | hashtable, 5 keys | The actions being resolved. Each `@{ Action; Parameters }` entry may carry `Machine = "PC/Work"` and/or `LayoutMachine = "Laptop/Work"`; an absent or blank key means every machine, and an action runs only when both scopes match. |
| [`ValidMachineTypes`](../../configuration-reference.md#valid-machine-types) | array of strings | `@("Test")` | The tokens a `Machine` scope may name. Anything else is reported as an unknown token and never matches. |
| [`LayoutMachineTypeOverrides`](../../configuration-reference.md#layout-set-overrides) | hashtable of machine type to layout set | `@{ Test = "" }` | Redirects a machine's layouts to another set. Every non-empty value is also a valid `LayoutMachine` token, and a redirected machine matches `LayoutMachine` scopes as that set, not as itself. |
| [`SmallDisplayMachineType`](../../configuration-reference.md#layout-set-overrides) | string | `""` | The layout set a small (laptop-class) primary display uses when no override applies. Also a valid `LayoutMachine` token. |

## Decisions

1. Does an action belong to a machine, or to a monitor setup?
    - Options: `Machine` for identity - an application that only exists or only makes sense on one machine (`@{ Action = "Open-Outlook"; Machine = "Work" }`). `LayoutMachine` for anything that produces windows the layout has to place - a browser opened twice for a two-zone layout (`Instances = 2`) needs a one-window twin scoped to the layout sets whose layout wants one window.
    - Default: No scope. Every action runs everywhere, which is right for every action that is the same on every machine.
    - More detail: [`WorkspaceActions`](../../configuration-reference.md#workspace-actions)
2. Which layout set does each machine actually resolve to?
    - Options: The detected type unless `LayoutMachineTypeOverrides` redirects it or `SmallDisplayMachineType` applies on a small display. A `LayoutMachine` scope has to name the set the machine resolves to, not the machine: with `PC = "Work"` in the overrides, the PC matches `LayoutMachine = "Work"` and not `LayoutMachine = "PC"` until the override is cleared. Run `Get-LayoutMachineType` to see what a machine resolves to right now.
    - Default: Every machine resolves to its own type (the base ships no override and no small-display set).
    - More detail: [`LayoutMachineTypeOverrides`](../../configuration-reference.md#layout-set-overrides)
3. Is every token a known type or layout set?
    - Options: `Machine` tokens must be in `ValidMachineTypes`. `LayoutMachine` tokens may additionally be any non-empty `LayoutMachineTypeOverrides` value or the `SmallDisplayMachineType`. A token that is neither is reported with the workspace and action named and never matches - so a typo skips the action loudly rather than silently. `All` is always valid.
    - Default: The shipped `Test` type.
    - More detail: [`ValidMachineTypes`](../../configuration-reference.md#valid-machine-types)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on each workspace's action array: `WorkspaceActions` itself merges per workspace name, but the array under a name is the complete list for that workspace.

## Steps Overview

1. Scope the actions in `WorkspaceActions`
2. Check the layout sets the scopes name
3. Reload and confirm the merge landed

## Step 1: Scope the actions in `WorkspaceActions`

Add `Machine` and/or `LayoutMachine` to the entries that differ per machine. Every other entry stays as it is. Here the desktop's own layout wants two Google windows side by side, and the laptop's and the work machine's layouts want one fullscreen window:

```powershell
WorkspaceActions = @{
    Gaming = @(
        @{ Action = "Open-Steam" }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google"); Instances = 2 }; LayoutMachine = "PC" }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") };               LayoutMachine = "Laptop/Work" }
        @{ Action = "Open-Outlook"; Machine = "Work" }
        @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Gaming" } }
    )
}
```

## Step 2: Check the layout sets the scopes name

A `LayoutMachine` token is a layout set. The machine types in `ValidMachineTypes` are layout sets too, and so is every non-empty `LayoutMachineTypeOverrides` value and the `SmallDisplayMachineType`. Nothing needs adding for the example above; a scope that names a set such as `Temp` needs that set to exist as an override value (and a `<Workspace>_Temp.psd1` layout file for the workspace).

```powershell
LayoutMachineTypeOverrides = @{
    PC = "Temp"
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.WorkspaceActions.Gaming
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Get-LayoutMachineType
Resolve-WorkspaceActions -Actions $global:Configuration.WorkspaceActions.Gaming -Workspace "Gaming" | ForEach-Object { $_.Action }
Resolve-WorkspaceActions -Actions $global:Configuration.WorkspaceActions.Gaming -Workspace "Gaming" -MachineType "Laptop" -LayoutMachineType "Laptop" | ForEach-Object { $_.Action }
```

The first call shows what this machine runs; the second what the laptop would run. An unknown token shows up here as an `Unknown machine type [...] in [WorkspaceActions.Gaming [Open-Browser]]` error, and a workspace whose every action is scoped elsewhere warns that nothing applies. `Set-LogLevel Verbose { Open-Workspace Gaming }` prints one `Skipping [...]` line per action the scope left out.

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    ValidMachineTypes = @("PC", "Laptop", "Work", "Test")
    LayoutMachineTypeOverrides = @{
        PC     = ""
        Laptop = ""
        Work   = ""
        Test   = ""
    }
    SmallDisplayMachineType = "Laptop"
    WorkspaceActions = @{
        Gaming = @(
            @{ Action = "Open-Steam" }
            @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google"); Instances = 2 }; LayoutMachine = "PC" }
            @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") };               LayoutMachine = "Laptop/Work" }
            @{ Action = "Open-Outlook"; Machine = "Work" }
            @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Gaming" } }
        )
    }
}
```

## Related

- [`Resolve-WorkspaceActions` in the Workflow module reference](../../../modules/workflow.md#resolve-workspaceactions) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [`Open-Workspace`](Open-Workspace.md) - runs the resolved list
- [`Measure-WorkspaceOpen`](Measure-WorkspaceOpen.md) - checks the resolved list before an experiment
- [`Test-MachineTypeScope`](../bootstrap/Test-MachineTypeScope.md) - the scope-string gate both keys go through
- [`Get-LayoutMachineType`](../window/Get-LayoutMachineType.md) - the layout set `LayoutMachine` is matched against
- [Machine Types](../../machine-types.md) - how a machine is detected and how its layouts can be redirected
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
