# Add-Workspace

Adds a workspace to `Configuration.psd1` by appending its `WorkspaceActions` entry - the workspace's only definition, and its place in the `Open-Workspace` menu.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).
>
> Direction: **writes** configuration. This function edits `Configuration.psd1` in place rather than reading it, so the "Where to Put Values" section below describes what it produces, not what you type by hand. Every write first copies the file into the unified [backup sink](../../../reference/backups.md) (`Backups/Windows/Config/Configuration/<timestamp>/`) as a one-click undo; a write whose backup cannot be taken is aborted.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`WorkspaceActions`](../../configuration-reference.md#workspace-actions) | ordered list of workspaces (one single-key hashtable each) | list of 5 | Every workspace `Open-Workspace` offers, in menu order: the workspace name is the key, the value is the ordered array of `@{ Action; Parameters }` entries opening it runs. An entry may carry `Machine` / `LayoutMachine` scopes and `MachineParameters` / `LayoutMachineParameters` tables ([Resolve-WorkspaceActions](../workflow/Resolve-WorkspaceActions.md)); `Add-Workspace` writes them through unchanged. `Close-Workspace` reads what the open actually produced, not this list. |

## Decisions

1. What should opening this workspace do?
    - Options: An ordered array of actions - any exported function name plus its `Parameters`. Typical: `Open-Project`, `Open-Browser`, `Open-Terminal`, `Set-WorkspaceWindowLayout`, `Focus-VirtualDesktop`.
    - Default: The shipped five workspaces.
    - More detail: [`WorkspaceActions`](../../configuration-reference.md#workspace-actions)
2. Where should the open finish?
    - Options: Put `Set-WorkspaceWindowLayout` after everything that creates windows, and `Focus-VirtualDesktop` last - it is meant to be the final desktop transition.
    - Default: The shipped ordering.
    - More detail: [`WorkspaceActions`](../../configuration-reference.md#workspace-actions)
3. Which workspaces should `Open-Workspace` offer, and in what order?
    - Options: One entry per workspace, in menu order - see [Add New Workspace](../workflow/add-new-workspace.md) for the whole walk. The list replaces wholesale, so include the shipped entries you still want.
    - Default: The shipped five.
    - More detail: [`WorkspaceActions`](../../configuration-reference.md#workspace-actions)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `WorkspaceActions` - it is an ordered list, so whatever you write is the complete value.

## Steps Overview

1. Set `WorkspaceActions`
2. Reload and confirm the merge landed

## Step 1: Set `WorkspaceActions`

Every workspace `Open-Workspace` offers, in the order the menu offers them. Each entry is a single-key hashtable: the key is the workspace name, the value is the ordered array of `@{ Action; Parameters }` entries opening it runs. There is no separate workspace list - defining a workspace here is what puts it in the menu, and `Add-Workspace` appends its entry at the end. `Close-Workspace` reads what the open actually produced, not this list.

Pass `-Actions` entries with `Machine` or `LayoutMachine` keys to scope an action to some machines, or with a `MachineParameters` / `LayoutMachineParameters` table to vary its parameters per machine; the tables are serialized after `Parameters` and the scopes last.

```powershell
WorkspaceActions = @(
    @{ MyWorkspace = @(
            @{ Action = "Open-Project"; Parameters = @{ ProjectName = "MyProject" } }
            @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Monitoring") }; LayoutMachineParameters = @{ PC = @{ Instances = 2 } } }
            @{ Action = "Open-Outlook"; Machine = "Work" }
            @{ Action = "Set-WorkspaceWindowLayout" }
        )
    }
)
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.WorkspaceActions
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.WorkspaceActions
Get-OrderedNames $global:Configuration.WorkspaceActions
Get-OrderedEntry $global:Configuration.WorkspaceActions "MyWorkspace"
$global:Configuration.WorkspaceActions.MyWorkspace
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    WorkspaceActions = @{
        MyWorkspace = @(
            @{ Action = "Open-Project"; Parameters = @{ ProjectName = "MyProject" } }
            @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Monitoring") } }
            @{ Action = "Set-WorkspaceWindowLayout" }
        )
    }
}
```

## Related

- [`Add-Workspace` in the Configuration module reference](../../../modules/configuration.md#add-workspace) - parameters, usage and behaviour
- [Configuration configuration guides](README.md) - every guide for this module
- [`Open-Workspace`](../workflow/Open-Workspace.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
