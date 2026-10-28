# Add-Project

Adds a project to `Configuration.psd1`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).
>
> Direction: **writes** configuration. This function edits `Configuration.psd1` in place rather than reading it, so the "Where to Put Values" section below describes what it produces, not what you type by hand. Every write first copies the file into the unified [backup sink](../../../reference/backups.md) (`Backups/Windows/Config/Configuration/<timestamp>/`) as a one-click undo; a write whose backup cannot be taken is aborted.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`ProjectActions`](../../configuration-reference.md#project-actions) | ordered list of projects (one single-key hashtable each) | list of 3 | Every project `Open-Project` offers, in menu order: the project name is the key, the value is the ordered array of `@{ Action; Parameters }` entries opening it runs. `Close-Project` reads the same list to work out what to close. |
| [`ProjectTerminals`](../../configuration-reference.md#project-terminals) | array of `@{ Name; BasePath; Paths }` | array of 3 | Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and where each one starts. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable. |
| [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings) | array of `@{ Name; Commands; ... }` | array of 2 | Every project `Run-Project` offers, in menu order, with the command each of its terminal paths runs. |

## Decisions

1. What should opening this project do?
    - Options: An ordered array of actions. Common ones: `Open-VSCode`, `Open-Terminal`, `Open-Browser`, `Open-VisualStudio`, `Run-Project`. Each takes a `Parameters` hashtable.
    - Default: The shipped example actions for the example projects.
    - More detail: [`ProjectActions`](../../configuration-reference.md#project-actions)
2. Does the order matter for your project?
    - Options: Actions run top to bottom. Put the editor first and the browser last if you want focus to land on the browser.
    - Default: The order you list them.
    - More detail: [`ProjectActions`](../../configuration-reference.md#project-actions)
3. Which terminal tabs should open for this project?
    - Options: One entry per project, naming the path keys its tabs start in.
    - Default: The shipped three entries.
    - More detail: [`ProjectTerminals`](../../configuration-reference.md#project-terminals)
4. Should `Run-Project` offer this project, and what does each of its paths run?
    - Options: One entry per runnable project, with `Commands` keyed by the `ProjectTerminals` path.
    - Default: The shipped two.
    - More detail: [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ProjectActions`, `ProjectTerminals`, `RunnableProjectMappings` - those keys are lists, so whatever you write is the complete value.

## Steps Overview

1. Set `ProjectActions`
2. Set `ProjectTerminals`
3. Set `RunnableProjectMappings`
4. Reload and confirm the merge landed

## Step 1: Set `ProjectActions`

Every project `Open-Project` offers, in the order the menu offers them. Each entry is a single-key hashtable: the key is the project name, the value is the ordered array of `@{ Action; Parameters }` entries opening it runs, where `Action` is any exported function name. There is no separate project list - defining a project here is what puts it in the menu. `Close-Project` reads the same list to work out what to close.

```powershell
ProjectActions = @(
    @{ MyProject = @(
            @{ Action = "Open-VSCode";   Parameters = @{ Project = "MyProject" } }
            @{ Action = "Open-Terminal"; Parameters = @{ Title = "MyProject" } }
        )
    }
)
```

## Step 2: Set `ProjectTerminals`

Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and where each one starts. `Paths` names keys under the project's `PathTemplates` entry; `ROOT` is the project root.

```powershell
ProjectTerminals = @(
    @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("API", "UI") }
)
```

## Step 3: Set `RunnableProjectMappings`

Every project `Run-Project` offers, in menu order. `Commands` is keyed by the `ProjectTerminals` path the command runs in; a path with no command listed just gets its terminal tab.

```powershell
RunnableProjectMappings = @(
    @{ Name     = "MyProject";
        Commands = @{ API = "dnr"; UI = "nir" }
    }
)
```

## Step 4: Reload and confirm the merge landed

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
Get-OrderedNames $global:Configuration.ProjectActions
Get-OrderedEntry $global:Configuration.ProjectActions "MyProject"
$global:Configuration.ProjectTerminals
$global:Configuration.RunnableProjectMappings.Name
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    ProjectActions = @(
        @{ MyProject = @(
                @{ Action = "Open-VSCode";   Parameters = @{ Project = "MyProject" } }
                @{ Action = "Open-Terminal"; Parameters = @{ Title = "MyProject" } }
            )
        }
    )
    ProjectTerminals = @(
        @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("API", "UI") }
    )
    RunnableProjectMappings = @(
        @{ Name     = "MyProject";
            Commands = @{ API = "dnr"; UI = "nir" }
        }
    )
}
```

## Related

- [`Add-Project` in the Configuration module reference](../../../modules/configuration.md#add-project) - parameters, usage and behaviour
- [Configuration configuration guides](README.md) - every guide for this module
- [`Close-Project`](../workflow/Close-Project.md) - reads the same configuration
- [`Open-Project`](../workflow/Open-Project.md) - reads the same configuration
- [`Resolve-ProjectPath`](../helper/Resolve-ProjectPath.md) - reads the same configuration
- [`Run-Project`](../helper/Run-Project.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
