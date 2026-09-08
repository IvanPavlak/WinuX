# Resolve-WorkspaceActions

Decides which of a workspace's configured actions run on this machine and with which parameters: an action runs when its `Machine` scope covers the detected machine type and its `LayoutMachine` scope covers the layout set the window layout will be read from, and its `MachineParameters` / `LayoutMachineParameters` rows for this machine are merged over its `Parameters`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`WorkspaceActions`](../../configuration-reference.md#workspace-actions) | hashtable of workspace name to action array | hashtable, 5 keys | The actions being resolved. Each `@{ Action; Parameters }` entry may carry the scopes `Machine = "PC/Work"` and/or `LayoutMachine = "Laptop/Work"` (an absent or blank key means every machine; the action runs only when both match) and the tables `MachineParameters` / `LayoutMachineParameters = @{ "<scope>" = @{ ... } }`, whose rows for this machine are merged over `Parameters` (`$null` removes a parameter). |
| [`ValidMachineTypes`](../../configuration-reference.md#valid-machine-types) | array of strings | `@("Test")` | The tokens a `Machine` scope or a `MachineParameters` row key may name. Anything else is reported as an unknown token and never matches. |
| [`LayoutMachineTypeOverrides`](../../configuration-reference.md#layout-set-overrides) | hashtable of machine type to layout set | `@{ Test = "" }` | Redirects a machine's layouts to another set. Every non-empty value is also a valid `LayoutMachine` token and `LayoutMachineParameters` row key, and a redirected machine matches those as that set, not as itself. |
| [`SmallDisplayMachineType`](../../configuration-reference.md#layout-set-overrides) | string | `""` | The layout set a small (laptop-class) primary display uses when no override applies. Also a valid `LayoutMachine` token and `LayoutMachineParameters` row key. |

## Decisions

1. Does an action belong to a machine, or to a monitor setup?
    - Options: The identity axis (`Machine`, `MachineParameters`) for an application that only exists or only makes sense on one machine (`@{ Action = "Open-Outlook"; Machine = "Work" }`). The layout axis (`LayoutMachine`, `LayoutMachineParameters`) for anything that produces windows the layout has to place - a window count has to agree with the layout file that will be read, even while a machine is redirected to another layout set.
    - Default: No machine key at all. Every action runs everywhere with the same parameters, which is right for every action that is the same on every machine.
    - More detail: [`WorkspaceActions`](../../configuration-reference.md#workspace-actions)
2. Scope the whole action, or vary its parameters?
    - Options: A scope (`Machine`, `LayoutMachine`) when the action should not run at all on the other machines. A table (`MachineParameters`, `LayoutMachineParameters`) when the action runs everywhere and only a parameter differs: `Parameters` is the default, each row holds the difference for the machines its key covers, rows merge over a copy of `Parameters` (`All` first, then the other matching rows alphabetically, `MachineParameters` before `LayoutMachineParameters`), and a value of `$null` removes the parameter. One entry with `Parameters = @{ Groups = @("Google") }` and `LayoutMachineParameters = @{ PC = @{ Instances = 2 } }` replaces two entries scoped `LayoutMachine = "PC"` and `LayoutMachine = "Laptop/Work"`.
    - Default: A table whenever the action runs everywhere - duplicating an entry per machine is never needed.
    - More detail: [`WorkspaceActions`](../../configuration-reference.md#workspace-actions)
3. Which layout set does each machine actually resolve to?
    - Options: The detected type unless `LayoutMachineTypeOverrides` redirects it or `SmallDisplayMachineType` applies on a small display. A `LayoutMachine` scope or `LayoutMachineParameters` row has to name the set the machine resolves to, not the machine: with `PC = "Work"` in the overrides, the PC matches `Work` and not `PC` until the override is cleared. Run `Get-LayoutMachineType` to see what a machine resolves to right now.
    - Default: Every machine resolves to its own type (the base ships no override and no small-display set).
    - More detail: [`LayoutMachineTypeOverrides`](../../configuration-reference.md#layout-set-overrides)
4. Is every token a known type or layout set?
    - Options: `Machine` tokens and `MachineParameters` row keys must be in `ValidMachineTypes`. `LayoutMachine` tokens and `LayoutMachineParameters` row keys may additionally be any non-empty `LayoutMachineTypeOverrides` value or the `SmallDisplayMachineType`. A token that is neither is reported with the workspace, action (and table) named and never matches - so a typo skips the action or row loudly rather than silently. `All` is always valid.
    - Default: The shipped `Test` type.
    - More detail: [`ValidMachineTypes`](../../configuration-reference.md#valid-machine-types)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on each workspace's action array: `WorkspaceActions` itself merges per workspace name, but the array under a name is the complete list for that workspace.

## Steps Overview

1. Scope or vary the actions in `WorkspaceActions`
2. Check the layout sets the scopes and rows name
3. Reload and confirm the merge landed

## Step 1: Scope or vary the actions in `WorkspaceActions`

Add a scope (`Machine`, `LayoutMachine`) to an entry that should not run everywhere, and a table (`MachineParameters`, `LayoutMachineParameters`) to an entry that runs everywhere with a difference per machine. Every other entry stays as it is. Here the desktop's own layout wants two Google windows side by side while the laptop's and the work machine's layouts want one fullscreen window, Outlook belongs to the work machine only, and the project is opened without running it away from the desktop:

```powershell
WorkspaceActions = @{
    Gaming = @(
        @{ Action = "Open-Steam" }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") }; LayoutMachineParameters = @{ PC = @{ Instances = 2 } } }
        @{ Action = "Open-Project"; Parameters = @{ Project = "Mods"; RunApp = $true }; MachineParameters = @{ "Laptop/Work" = @{ RunApp = $null } } }
        @{ Action = "Open-Outlook"; Machine = "Work" }
        @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "Gaming" } }
    )
}
```

## Step 2: Check the layout sets the scopes and rows name

A `LayoutMachine` token or `LayoutMachineParameters` row key is a layout set. The machine types in `ValidMachineTypes` are layout sets too, and so is every non-empty `LayoutMachineTypeOverrides` value and the `SmallDisplayMachineType`. Nothing needs adding for the example above; a scope or row that names a set such as `Temp` needs that set to exist as an override value (and a `<Workspace>_Temp.psd1` layout file for the workspace).

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
Resolve-WorkspaceActions -Actions $global:Configuration.WorkspaceActions.Gaming -Workspace "Gaming" | ForEach-Object { "$($_.Action) $(($_.Parameters.Keys | Sort-Object) -join ',')" }
Resolve-WorkspaceActions -Actions $global:Configuration.WorkspaceActions.Gaming -Workspace "Gaming" -MachineType "Laptop" -LayoutMachineType "Laptop" | ForEach-Object { "$($_.Action) $(($_.Parameters.Keys | Sort-Object) -join ',')" }
```

The first call shows what this machine runs and with which parameters; the second what the laptop would run (`Open-Browser` without `Instances`, `Open-Project` without `RunApp`, no `Open-Outlook`). An unknown token shows up here as an `Unknown machine type [...] in [WorkspaceActions.Gaming [Open-Browser]]` error (with `.LayoutMachineParameters` appended for a row key), and a workspace whose every action is scoped elsewhere warns that nothing applies. `Set-LogLevel Verbose { Open-Workspace Gaming }` prints one `Skipping [...]` line per action the scope left out and one `... applied on [...]` line per table row that was merged.

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
            @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Google") }; LayoutMachineParameters = @{ PC = @{ Instances = 2 } } }
            @{ Action = "Open-Project"; Parameters = @{ Project = "Mods"; RunApp = $true }; MachineParameters = @{ "Laptop/Work" = @{ RunApp = $null } } }
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
