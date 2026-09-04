# Open-Workspace

The main entry point for starting work. Alias: `w`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DefaultVSCodeWorkspaces`](../../configuration-reference.md#default-vs-code-workspaces) | hashtable of workspace name to VS Code workspace file | `@{}` (empty) | Which `.code-workspace` file `Open-Workspace` opens for a given WinuX workspace. |
| [`DefaultWorkspace`](../../configuration-reference.md#default-workspace) | string | `"Default"` | Which workspace `Open-Workspace` opens with no argument. |
| [`ProjectTerminals`](../../configuration-reference.md#project-terminals) | array of `@{ Project; Tabs; ... }` | array of 3 | Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and with what titles and starting directories. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable. |
| [`WorkspaceActions`](../../configuration-reference.md#workspace-actions) | hashtable of workspace name to action array | hashtable, 5 keys | What `Open-Workspace` does for each workspace: an ordered array of `@{ Action; Parameters }` entries. `Close-Workspace` reads what the open actually produced, not this map. |
| [`WorkspaceBenchmark`](../../configuration-reference.md#workspace-benchmark) | hashtable (`Enabled`, `Display`, `Last`) | `@{ Enabled = $false; Display = "Table"; Last = 10 }` | Whether every open is measured - each action timed, the layout phases read back, one row appended to `WorkspaceBenchmark.csv` - and what the end of the open shows: the workspace's recent runs as a table, one `Timing =>` line, or nothing. |
| [`Workspaces`](../../configuration-reference.md#workspaces-list) | array of workspace names | `@("Default", "Example", "Fullscreen", "Empty", "WinuX")` | The workspace names `Open-Workspace` offers. Each needs a `WorkspaceActions` entry to do anything. |
| [`WorkspaceLayoutPrepareEarly`](../../configuration-reference.md#layout-numbers--zone-mappings) | bool | `$true` | Whether the layout's virtual desktops and FancyZones zone layouts are prepared before the launch actions (`Set-WorkspaceWindowLayout -PrepareOnly`), on an idle machine, or left to the layout action after them. |

Action order is the whole of the behaviour here. Everything that creates a window runs first, `Set-WorkspaceWindowLayout` places them, and `Focus-VirtualDesktop` is meant to be the last thing that happens - a workspace that ends by jumping to another desktop and back almost always has an action after the focus call.

## Decisions

1. Should any workspace open a specific VS Code workspace file?
    - Options: Workspace name to `.code-workspace` filename (resolved under the VS Code workspaces directory).
    - Default: Empty - no VS Code workspace is opened automatically.
    - More detail: [`DefaultVSCodeWorkspaces`](../../configuration-reference.md#default-vs-code-workspaces)
2. Which workspace should open when you type `Open-Workspace` with no argument?
    - Options: A name from `Workspaces`.
    - Default: `Default`.
    - More detail: [`DefaultWorkspace`](../../configuration-reference.md#default-workspace)
3. Which terminal tabs should open for this project?
    - Options: One entry per project with its tab list. Each tab can set a title and a starting directory, and can run in WSL.
    - Default: The shipped three entries.
    - More detail: [`ProjectTerminals`](../../configuration-reference.md#project-terminals)
4. What should opening this workspace do?
    - Options: An ordered array of actions - any exported function name plus its `Parameters`. Typical: `Open-Project`, `Open-Browser`, `Open-Terminal`, `Set-WorkspaceWindowLayout`, `Focus-VirtualDesktop`.
    - Default: The shipped five workspaces.
    - More detail: [`WorkspaceActions`](../../configuration-reference.md#workspace-actions)
5. Where should the open finish?
    - Options: Put `Set-WorkspaceWindowLayout` after everything that creates windows, and `Focus-VirtualDesktop` last - it is meant to be the final desktop transition.
    - Default: The shipped ordering.
    - More detail: [`WorkspaceActions`](../../configuration-reference.md#workspace-actions)
6. Which workspaces should `Open-Workspace` offer?
    - Options: One name per workspace - see [Add New Workspace](../workflow/add-new-workspace.md) for the whole walk. The array replaces wholesale, so include the shipped names you still want.
    - Default: The shipped five.
    - More detail: [`Workspaces`](../../configuration-reference.md#workspaces-list)
7. Should every workspace open be measured?
    - Options: `Enabled = $true` records one row per open in `WorkspaceBenchmark.csv`; `Display` picks what the end of the open shows - `"Table"` (the workspace's recent runs), `"Line"` (one `Timing =>` line) or `"None"` (record only); `Last` sets how many runs the table shows.
    - Default: Off - nothing is recorded and nothing extra is printed.
    - More detail: [`WorkspaceBenchmark`](../../configuration-reference.md#workspace-benchmark)
8. Should the layout's desktops and zone layouts be prepared before the applications launch?
    - Options: `$true` runs the layout preamble first, on an idle machine; `$false` leaves all of it to the layout action after the launch actions.
    - Default: `$true`. Switch it off to compare the two with `Get-WorkspaceBenchmark`, or if a workspace misbehaves only with the preparation on.
    - More detail: [`WorkspaceLayoutPrepareEarly`](../../configuration-reference.md#layout-numbers--zone-mappings)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ProjectTerminals`, `Workspaces` - those keys are arrays, so whatever you write is the complete value. `WorkspaceBenchmark` is a hashtable and deep-merges, so `@{ Enabled = $true }` alone opts in and keeps the shipped `Display` and `Last`.

## Steps Overview

1. Set `DefaultVSCodeWorkspaces`
2. Set `DefaultWorkspace`
3. Set `ProjectTerminals`
4. Set `WorkspaceActions`
5. Set `Workspaces`
6. Set `WorkspaceBenchmark`
7. Set `WorkspaceLayoutPrepareEarly`
8. Reload and confirm the merge landed

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

Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and with what titles and starting directories. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable.

```powershell
ProjectTerminals = @(
    @{ Project = "MyProject"; Tabs = @(
        @{ Title = "MyProject"; Path = "{Dev}\MyProject" }
    )}
)
```

## Step 4: Set `WorkspaceActions`

What `Open-Workspace` does for each workspace: an ordered array of `@{ Action; Parameters }` entries. `Close-Workspace` reads what the open actually produced, not this map.

```powershell
WorkspaceActions = @{
    MyWorkspace = @(
        @{ Action = "Open-Project"; Parameters = @{ ProjectName = "MyProject" } }
        @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Monitoring") } }
        @{ Action = "Set-WorkspaceWindowLayout" }
    )
}
```

## Step 5: Set `Workspaces`

The workspace names `Open-Workspace` offers. Each needs a `WorkspaceActions` entry to do anything.

```powershell
Workspaces = @("Default", "MyWorkspace")
```

## Step 6: Set `WorkspaceBenchmark`

Whether every open is measured and what the end of the open shows. Off in the base. With `Enabled = $true` and the default `Display = "Table"`, every `w MyWorkspace` ends with the workspace's recent runs as a table - the same output as `Get-WorkspaceBenchmark -Workspace MyWorkspace -Formatted` - before the elapsed summary. `"Line"` prints one `Timing [MyWorkspace] => actions 0.8s | fancyzones 3.8s | wait 15.1s | ...` line instead, `"None"` only records. The flag alone is enough; `Display` and `Last` deep-merge from the base.

```powershell
WorkspaceBenchmark = @{
    Enabled = $true
}
```

## Step 7: Set `WorkspaceLayoutPrepareEarly`

Whether `Open-Workspace` runs the layout preamble - virtual desktop resize and FancyZones zone layouts, as `Set-WorkspaceWindowLayout -PrepareOnly` - before the launch actions. On in the base; the layout action then finds that work done and skips it. Set `$false` to run the whole layout after the launch actions, for comparison with `Get-WorkspaceBenchmark` or as an escape hatch.

```powershell
WorkspaceLayoutPrepareEarly = $false
```

## Step 8: Reload and confirm the merge landed

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
$global:Configuration.ProjectTerminals
$global:Configuration.WorkspaceActions
$global:Configuration.Workspaces
$global:Configuration.WorkspaceBenchmark
$global:Configuration.WorkspaceLayoutPrepareEarly
$global:Configuration.Workspaces
$global:Configuration.WorkspaceActions.Keys
$global:Configuration.DefaultWorkspace
```

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
        @{ Project = "MyProject"; Tabs = @(
            @{ Title = "MyProject"; Path = "{Dev}\MyProject" }
        )}
    )
    WorkspaceActions = @{
        MyWorkspace = @(
            @{ Action = "Open-Project"; Parameters = @{ ProjectName = "MyProject" } }
            @{ Action = "Open-Browser"; Parameters = @{ Groups = @("Monitoring") } }
            @{ Action = "Set-WorkspaceWindowLayout" }
        )
    }
    Workspaces = @("Default", "MyWorkspace")
    WorkspaceBenchmark = @{
        Enabled = $true
    }
    WorkspaceLayoutPrepareEarly = $true
}
```

## Related

- [`Open-Workspace` in the Workflow module reference](../../../modules/workflow.md#open-workspace) - parameters, usage and behaviour
- [`Get-WorkspaceBenchmark`](Get-WorkspaceBenchmark.md) - reads the rows the benchmark records
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [`Add-Project`](../configuration/Add-Project.md) - reads the same configuration
- [`Resolve-ProjectPath`](../helper/Resolve-ProjectPath.md) - reads the same configuration
- [`Run-Project`](../helper/Run-Project.md) - reads the same configuration
- [`Open-ProjectTerminals`](Open-ProjectTerminals.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
