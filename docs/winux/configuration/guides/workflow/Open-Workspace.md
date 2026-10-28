# Open-Workspace

The main entry point for starting work. Alias: `w`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DefaultVSCodeWorkspaces`](../../configuration-reference.md#default-vs-code-workspaces) | hashtable of workspace name to VS Code workspace file | `@{}` (empty) | Which `.code-workspace` file `Open-Workspace` opens for a given WinuX workspace. |
| [`DefaultWorkspace`](../../configuration-reference.md#default-workspace) | string | `"Default"` | Which workspace `Open-Workspace` opens with no argument. |
| [`ProjectActions`](../../configuration-reference.md#project-actions) | ordered list of projects | ordered list | The project menu `Open-Workspace` shows up front when the workspace's `Open-Project` action has no fixed project, and the valid tokens of the `Project` / `ProjectParameters` keys. |
| [`ProjectTerminals`](../../configuration-reference.md#project-terminals) | array of `@{ Name; BasePath; Paths }` | array of 3 | Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and where each one starts. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable. |
| [`WorkspaceActions`](../../configuration-reference.md#workspace-actions) | ordered list of workspaces (one single-key hashtable each) | list of 5 | Every workspace `Open-Workspace` offers, in menu order: the workspace name is the key, the value is the ordered array of `@{ Action; Parameters }` entries opening it runs. An entry may carry `Machine = "PC/Work"` and/or `LayoutMachine = "Laptop/Work"` to run only there, or a `MachineParameters` / `LayoutMachineParameters` table to vary its parameters per machine ([Resolve-WorkspaceActions](Resolve-WorkspaceActions.md)). `Close-Workspace` reads what the open actually produced, not this list. An entry may also carry `Project = "MyProject/OtherProject"` or a `ProjectParameters` table for the project(s) the open is for, and a whole workspace may be a templated entry `@{ <Name> = @{ Template = "<template>"; Variables; Overrides; Add } }`. `{Workspace}` is the workspace's own name in any value. |
| [`WorkspaceTemplates`](../../configuration-reference.md#workspace-templates) | hashtable of template name to `@{ Variables; Actions }` | `@{ Project = ... }` | The action lists templated workspaces stamp out. A command-line `-<Variable> <value>` sets a template variable for one open and is not forwarded to the actions. |
| [`WorkspaceBenchmark`](../../configuration-reference.md#workspace-benchmark) | hashtable (`Enabled`, `Display`, `Last`) | `@{ Enabled = $false; Display = "Table"; Last = 10 }` | Whether every open is measured - each action timed, the layout phases read back, one row appended to `WorkspaceBenchmark.csv` - and what the end of the open shows: the workspace's recent runs as a table, one `Timing =>` line, or nothing. |
| [`WorkspaceLayoutPrepareEarly`](../../configuration-reference.md#layout-numbers--zone-mappings) | bool | `$true` | Whether the layout's virtual desktops and FancyZones zone layouts are prepared before the launch actions (`Set-WorkspaceWindowLayout -PrepareOnly`), on an idle machine, or left to the layout action after them. |

Action order is the whole of the behaviour here. Everything that creates a window runs first, `Set-WorkspaceWindowLayout` places them, and `Focus-VirtualDesktop` is meant to be the last thing that happens - a workspace that ends by jumping to another desktop and back almost always has an action after the focus call.

## Decisions

1. Should any workspace open a specific VS Code workspace file?
    - Options: Workspace name to `.code-workspace` filename (resolved under the VS Code workspaces directory).
    - Default: Empty - no VS Code workspace is opened automatically.
    - More detail: [`DefaultVSCodeWorkspaces`](../../configuration-reference.md#default-vs-code-workspaces)
2. Which workspace should open when you type `Open-Workspace` with no argument?
    - Options: A name defined in `WorkspaceActions`.
    - Default: `Default`.
    - More detail: [`DefaultWorkspace`](../../configuration-reference.md#default-workspace)
3. Which terminal tabs should open for this project?
    - Options: One entry per project with its tab list. Each tab can set a title and a starting directory, and can run in WSL.
    - Default: The shipped three entries.
    - More detail: [`ProjectTerminals`](../../configuration-reference.md#project-terminals)
4. What should opening this workspace do?
    - Options: An ordered array of actions - any exported function name plus its `Parameters`. Typical: `Open-Project`, `Open-Browser`, `Open-Terminal`, `Set-WorkspaceWindowLayout`, `Focus-VirtualDesktop`. An action that should not run everywhere takes a `Machine` scope (detected machine type) or a `LayoutMachine` scope (the layout set the layout is read from); an action that runs everywhere but differs per machine keeps one entry and carries the difference in a `MachineParameters` or `LayoutMachineParameters` table - `Parameters = @{ Groups = @("Google") }` with `LayoutMachineParameters = @{ PC = @{ Instances = 2 } }` opens two windows on the PC's own layout set and one everywhere else; see [Resolve-WorkspaceActions](Resolve-WorkspaceActions.md). Every action that declares a `CurrentWorkspace` parameter also receives the workspace's own name - `Open-Obsidian` uses it to load the same-named Obsidian workspace, so a bare `@{ Action = "Open-Obsidian" }` is enough (see [Open-Obsidian](../application/Open-Obsidian.md)).
    - Default: The shipped five workspaces, none of them scoped.
    - More detail: [`WorkspaceActions`](../../configuration-reference.md#workspace-actions)
5. Where should the open finish?
    - Options: Put `Set-WorkspaceWindowLayout` after everything that creates windows, and `Focus-VirtualDesktop` last - it is meant to be the final desktop transition.
    - Default: The shipped ordering.
    - More detail: [`WorkspaceActions`](../../configuration-reference.md#workspace-actions)
6. Should every workspace open be measured?
    - Options: `Enabled = $true` records one row per open in `WorkspaceBenchmark.csv`; `Display` picks what the end of the open shows - `"Table"` (the workspace's recent runs), `"Line"` (one `Timing =>` line) or `"None"` (record only); `Last` sets how many runs the table shows.
    - Default: Off - nothing is recorded and nothing extra is printed.
    - More detail: [`WorkspaceBenchmark`](../../configuration-reference.md#workspace-benchmark)
7. Should the layout's desktops and zone layouts be prepared before the applications launch?
    - Options: `$true` runs the layout preamble first, on an idle machine; `$false` leaves all of it to the layout action after the launch actions.
    - Default: `$true`. Switch it off to compare the two with `Get-WorkspaceBenchmark`, or if a workspace misbehaves only with the preparation on.
    - More detail: [`WorkspaceLayoutPrepareEarly`](../../configuration-reference.md#layout-numbers--zone-mappings)
8. Do several workspaces share one action list?
    - Options: Write it once in `WorkspaceTemplates` and give each workspace a one-line templated entry (`@{ MyProject = @{ Template = "Project" } }`), with `Variables`, `Overrides` and `Add` for what differs; or keep plain action lists. A templated entry with errors stays in the menu and opens nothing.
    - Default: The shipped `WinuX` workspace uses the generic `Project` template; every other shipped workspace is a plain list.
    - More detail: [`WorkspaceTemplates`](../../configuration-reference.md#workspace-templates)
9. Does an action depend on the project the workspace is opened for?
    - Options: `Project = "MyProject/OtherProject"` to run it only for those projects, `ProjectParameters = @{ MyProject = @{ ... } }` to vary its parameters per project. The projects are known before anything launches - `-Project`, else the up-front project menu (when `Open-Project` has no fixed project), else the fixed `Open-Project` projects - and also pick the layout file's `ProjectOverrides`.
    - Default: No project keys - every action runs for every project with the same parameters.
    - More detail: [`WorkspaceActions`](../../configuration-reference.md#workspace-actions)
10. Which projects should the up-front project menu offer?
    - Options: One `ProjectActions` entry per project, in menu order; those names are also the only valid `Project` / `ProjectParameters` tokens.
    - Default: The shipped project list.
    - More detail: [`ProjectActions`](../../configuration-reference.md#project-actions)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ProjectActions`, `ProjectTerminals` and `WorkspaceActions` - those keys are lists, so whatever you write is the complete value. `WorkspaceBenchmark` is a hashtable and deep-merges, so `@{ Enabled = $true }` alone opts in and keeps the shipped `Display` and `Last`. `WorkspaceTemplates` merges template by template: a local template replaces the base template of the same name whole.

## Steps Overview

1. Set `DefaultVSCodeWorkspaces`
2. Set `DefaultWorkspace`
3. Set `ProjectTerminals`
4. Set `WorkspaceActions`
5. Set `WorkspaceBenchmark`
6. Set `WorkspaceTemplates`
7. Set `WorkspaceLayoutPrepareEarly`
8. Set `ProjectActions`
9. Reload and confirm the merge landed

## Step 1: Set `DefaultVSCodeWorkspaces`

Which `.code-workspace` file `Open-Workspace` opens for a given WinuX workspace.

```powershell
DefaultVSCodeWorkspaces = @{
    Default = "MyProject.code-workspace"
}
```

## Step 2: Set `DefaultWorkspace`

Which workspace `Open-Workspace` opens with no argument.

```powershell
DefaultWorkspace = "Default"
```

## Step 3: Set `ProjectTerminals`

Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project: `Name` is the project, `BasePath` a dot-notation reference into the expanded paths, and each `Paths` key one tab (titled `<Name>.<Key>`). `Open-Workspace` reads it to know which tab names belong to the workspace, so a rerun from one of its own project tabs does not close that tab. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable.

```powershell
ProjectTerminals = @(
    @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("API", "UI") }
)
```

## Step 4: Set `WorkspaceActions`

What `Open-Workspace` does for each workspace: an ordered array of `@{ Action; Parameters }` entries. `Close-Workspace` reads what the open actually produced, not this map. An entry that should only run on some machines carries `Machine = "PC/Work"` (detected machine type) and/or `LayoutMachine = "Laptop/Work"` (the layout set the window layout is read from); an entry whose parameters differ per machine carries a `MachineParameters` / `LayoutMachineParameters` table keyed by the same scope strings; the rest of the list is unaffected.

An entry that should only run for some projects carries `Project = "MyProject/OtherProject"`, and one whose parameters differ per project a `ProjectParameters` table. Here `Open-Project` has no fixed project, so the project menu is shown before anything launches and its choice drives `Open-DBeaver` and the browser groups.

```powershell
WorkspaceActions = @(
    @{ MyWorkspace = @(
            @{ Action = "Open-Project" }
            @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Monitoring") }; LayoutMachineParameters = @{ PC = @{ Instances = 2 } }; ProjectParameters = @{ MyProject = @{ Groups = @("Monitoring", "MyProjectDocs") } } }
            @{ Action = "Open-DBeaver"; Project = "MyProject" }
            @{ Action = "Open-Outlook"; Machine = "Work" }
            @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "{Workspace}" } }
        )
    }
    @{ MyRepo = @{ Template = "Project" } }
)
```

## Step 5: Set `WorkspaceBenchmark`

Whether every open is measured and what the end of the open shows. Off in the base. With `Enabled = $true` and the default `Display = "Table"`, every `w MyWorkspace` ends with the workspace's recent runs as a table - the same output as `Get-WorkspaceBenchmark -Workspace MyWorkspace -Formatted` - before the elapsed summary. `"Line"` prints one `Timing [MyWorkspace] => actions 0.8s | fancyzones 3.8s | wait 15.1s | ...` line instead, `"None"` only records. The flag alone is enough; `Display` and `Last` deep-merge from the base.

```powershell
WorkspaceBenchmark = @{
    Enabled = $true
}
```

## Step 6: Set `WorkspaceTemplates`

The action lists templated workspaces stamp out. A local template replaces the base template of the same name whole, so define a new name rather than half of `Project`. `Open-Workspace MyRepo -Repository OtherGroup` sets the `Repository` variable for one open.

```powershell
WorkspaceTemplates = @{
    Repo = @{
        Variables = @{ Repository = "{Workspace}" }
        Actions   = @(
            @{ Action = "Open-Browser"; Parameters = @{ Groups = @("{Repository}") } }
            @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{Workspace}" } }
            @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "{Workspace}" } }
            @{ Action = "Focus-VirtualDesktop"; Parameters = @{ DesktopNumber = 1 } }
        )
    }
}
```

## Step 7: Set `WorkspaceLayoutPrepareEarly`

Whether `Open-Workspace` runs the layout preamble - virtual desktop resize and FancyZones zone layouts, as `Set-WorkspaceWindowLayout -PrepareOnly` - before the launch actions. On in the base; the layout action then finds that work done and skips it. Set `$false` to run the whole layout after the launch actions, for comparison with `Get-WorkspaceBenchmark` or as an escape hatch.

```powershell
WorkspaceLayoutPrepareEarly = $false
```

## Step 8: Set `ProjectActions`

The projects `Open-Workspace` offers in its up-front project menu (shown when the workspace's `Open-Project` action has no fixed project), and the only valid tokens of an action's `Project` scope and `ProjectParameters` keys. It is a list, so a local value replaces the whole base list.

```powershell
ProjectActions = @(
    @{ MyProject = @( @{ Action = "Open-VSCode"; Parameters = @{ Folder = "MyProject" } } ) }
    @{ OtherProject = @( @{ Action = "Open-VSCode"; Parameters = @{ Folder = "OtherProject" } } ) }
)
```

## Step 9: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultVSCodeWorkspaces
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultVSCodeWorkspaces
$global:Configuration.DefaultWorkspace
Get-OrderedNames $global:Configuration.ProjectActions
$global:Configuration.ProjectTerminals
$global:Configuration.WorkspaceActions
$global:Configuration.WorkspaceBenchmark
$global:Configuration.WorkspaceLayoutPrepareEarly
$global:Configuration.WorkspaceTemplates
$global:Configuration.WorkspaceTemplateErrors
Get-OrderedNames $global:Configuration.WorkspaceActions
$global:Configuration.DefaultWorkspace
```

`WorkspaceTemplateErrors` lists every templated entry that did not expand at load; such a workspace logs its errors and opens nothing.

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultVSCodeWorkspaces = @{
        Default = "MyProject.code-workspace"
    }
    DefaultWorkspace = "Default"
    ProjectTerminals = @(
        @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("API", "UI") }
    )
    ProjectActions = @(
        @{ MyProject = @( @{ Action = "Open-VSCode"; Parameters = @{ Folder = "MyProject" } } ) }
        @{ OtherProject = @( @{ Action = "Open-VSCode"; Parameters = @{ Folder = "OtherProject" } } ) }
    )
    WorkspaceActions = @(
        @{ Default = @(
                @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI") } }
            )
        }
        @{ MyWorkspace = @(
                @{ Action = "Open-Project" }
                @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Monitoring") }; LayoutMachineParameters = @{ PC = @{ Instances = 2 } }; ProjectParameters = @{ MyProject = @{ Groups = @("Monitoring", "MyProjectDocs") } } }
                @{ Action = "Open-DBeaver"; Project = "MyProject" }
                @{ Action = "Open-Outlook"; Machine = "Work" }
                @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "{Workspace}" } }
            )
        }
        @{ MyRepo = @{ Template = "Repo" } }
    )
    WorkspaceTemplates = @{
        Repo = @{
            Variables = @{ Repository = "{Workspace}" }
            Actions   = @(
                @{ Action = "Open-Browser"; Parameters = @{ Groups = @("{Repository}") } }
                @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{Workspace}" } }
                @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "{Workspace}" } }
                @{ Action = "Focus-VirtualDesktop"; Parameters = @{ DesktopNumber = 1 } }
            )
        }
    }
    WorkspaceBenchmark = @{
        Enabled = $true
    }
    WorkspaceLayoutPrepareEarly = $true
}
```

## Related

- [`Open-Workspace` in the Workflow module reference](../../../modules/workflow.md#open-workspace) - parameters, usage and behaviour
- [`Resolve-WorkspaceActions`](Resolve-WorkspaceActions.md) - the `Machine` / `LayoutMachine` scopes and the `MachineParameters` / `LayoutMachineParameters` tables an action can carry
- [`Get-WorkspaceBenchmark`](Get-WorkspaceBenchmark.md) - reads the rows the benchmark records
- [`Resolve-WorkspaceTemplate`](../helper/Resolve-WorkspaceTemplate.md) - templated workspaces: variables, overrides and additions
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [`Add-Project`](../configuration/Add-Project.md) - reads the same configuration
- [`Resolve-ProjectPath`](../helper/Resolve-ProjectPath.md) - reads the same configuration
- [`Run-Project`](../helper/Run-Project.md) - reads the same configuration
- [`Open-ProjectTerminals`](Open-ProjectTerminals.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
