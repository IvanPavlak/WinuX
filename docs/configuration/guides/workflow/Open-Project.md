# Open-Project

Opens a development project with all its configured tools, applications and terminal tabs.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`ProjectActions`](../../configuration-reference.md#project-actions) | hashtable of project name to action array | hashtable, 3 keys | What `Open-Project` does for each project: an ordered array of `@{ Action; Parameters }` entries, where `Action` is any exported function name. `Close-Project` reads the same map to work out what to close. |
| [`Projects`](../../configuration-reference.md#projects-list) | array of project names | `@("WinuX", "ExampleProject", "Server")` | The project names `Open-Project` offers. A name here needs a matching `ProjectActions` entry to do anything, and usually a `PathTemplates.Projects` entry for its root. |

## Decisions

1. What should opening this project do?
    - Options: An ordered array of actions. Common ones: `Open-VSCode`, `Open-Terminal`, `Open-Browser`, `Open-VisualStudio`, `Run-Project`. Each takes a `Parameters` hashtable.
    - Default: The shipped example actions for the example projects.
    - More detail: [`ProjectActions`](../../configuration-reference.md#project-actions)
2. Does the order matter for your project?
    - Options: Actions run top to bottom. Put the editor first and the browser last if you want focus to land on the browser.
    - Default: The order you list them.
    - More detail: [`ProjectActions`](../../configuration-reference.md#project-actions)
3. Which projects should `Open-Project` offer?
    - Options: One name per project - see [Add New Project](../workflow/add-new-project.md) for the whole walk. The array replaces wholesale, so include the shipped names you still want.
    - Default: The shipped three.
    - More detail: [`Projects`](../../configuration-reference.md#projects-list)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `Projects` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `ProjectActions`
2. Set `Projects`
3. Reload and confirm the merge landed

## Step 1: Set `ProjectActions`

What `Open-Project` does for each project: an ordered array of `@{ Action; Parameters }` entries, where `Action` is any exported function name. `Close-Project` reads the same map to work out what to close.

```powershell
ProjectActions = @{
    MyProject = @(
        @{ Action = "Open-VSCode";   Parameters = @{ Project = "MyProject" } }
        @{ Action = "Open-Terminal"; Parameters = @{ Title = "MyProject" } }
    )
}
```

## Step 2: Set `Projects`

The project names `Open-Project` offers. A name here needs a matching `ProjectActions` entry to do anything, and usually a `PathTemplates.Projects` entry for its root.

```powershell
Projects = @("WinuX", "MyProject")
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.ProjectActions
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.ProjectActions
$global:Configuration.Projects
$global:Configuration.Projects
$global:Configuration.ProjectActions.Keys
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    ProjectActions = @{
        MyProject = @(
            @{ Action = "Open-VSCode";   Parameters = @{ Project = "MyProject" } }
            @{ Action = "Open-Terminal"; Parameters = @{ Title = "MyProject" } }
        )
    }
    Projects = @("WinuX", "MyProject")
}
```

## Related

- [`Open-Project` in the Workflow module reference](../../../modules/workflow.md#open-project) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [`Add-Project`](../configuration/Add-Project.md) - reads the same configuration
- [`Close-Project`](Close-Project.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
