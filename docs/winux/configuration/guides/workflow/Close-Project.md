# Close-Project

Closes all project-specific resources opened by `Open-Project` (Visual Studio windows, VSCode windows, Windows Terminal tabs, and browser tabs/windows), enabling fast switching between projects by closing only project-specific resources while keeping workspace-level applications running.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PathTemplates`](../../configuration-reference.md#path-templates--placeholder-system) | hashtable, 11 keys | hashtable, 11 keys (several ship empty) | Read through `$global:MachineSpecificPaths` (the expanded `PathTemplates`): the `Projects.<Name>.Solution` / `Projects.<Name>.Root` paths that `VisualStudioSolutions` and `VSCodeProjects` entries point at become extra window-title candidates, so a window whose title shows the real solution or folder name is matched even when it differs from the configured name. |
| [`ProjectActions`](../../configuration-reference.md#project-actions) | ordered list of projects (one single-key hashtable each) | list of 3 | Every project `Open-Project` offers, in menu order: the project name is the key, the value is the ordered array of `@{ Action; Parameters }` entries opening it runs, where `Action` is any exported function name. `Close-Project` reads the same list to work out what to close. |
| [`Universal`](../../configuration-reference.md#universal-constants) | hashtable, 27 keys | hashtable, 27 keys | Machine-independent constants: executable paths (`FirefoxExe`, `DockerExe`, `DbeaverExe`, ...), the `Browsers` map, `DefaultBrowser`, shared URLs, the `TerminateProcessNames` / `VisibleWindowExclusions` lists, and `Desktop` (auto-resolved at load). Expanded in place by `Load-PathConfiguration`, so placeholders work here too. `Close-Project` reads `DefaultBrowser` (the browser whose tabs it closes; empty skips browser cleanup) and `Browsers` (the name must be a key there). |
| [`VisualStudioSolutions`](../../configuration-reference.md#visual-studio-solutions) | array of `@{ Name; Solution }` (`Solution` is a dot-notation reference into the expanded paths) | array of 1 | The solutions `Open-VisualStudio` offers. `Close-Project` looks up an `Open-VisualStudio` action's `Solution` name here to resolve the real solution path for window matching. |
| [`VSCodeProjects`](../../configuration-reference.md#vs-code-projects) | array of `@{ Name; Path }` (`Path` is a dot-notation reference into the expanded paths) | array of 2 | The folders `Open-VSCode` offers by name. `Close-Project` looks up an `Open-VSCode` action's `Folder` name here to resolve the real folder path for window matching. |

Closing reads the same `ProjectActions` map the open used, so a project that opens cleanly and closes messily almost always means the action list and the reality drifted apart - an app opened by hand, or an action added without its counterpart.

## Decisions

1. What should opening this project do?
    - Options: An ordered array of actions. Common ones: `Open-VSCode`, `Open-Terminal`, `Open-Browser`, `Open-VisualStudio`, `Run-Project`. Each takes a `Parameters` hashtable.
    - Default: The shipped example actions for the example projects.
    - More detail: [`ProjectActions`](../../configuration-reference.md#project-actions)
2. Does the order matter for your project?
    - Options: Actions run top to bottom. Put the editor first and the browser last if you want focus to land on the browser.
    - Default: The order you list them.
    - More detail: [`ProjectActions`](../../configuration-reference.md#project-actions)
3. Which projects should `Open-Project` offer, and in what order?
    - Options: One entry per project, in menu order - see [Add New Project](../workflow/add-new-project.md) for the whole walk. The list replaces wholesale, so include the shipped entries you still want.
    - Default: The shipped three.
    - More detail: [`ProjectActions`](../../configuration-reference.md#project-actions)
4. Which browser should be the default?
    - Options: A key from `Universal.Browsers`: `Firefox`, `Chrome`, `Edge`, `Brave`, `Tor`. Ships empty, so `Open-Browser` warns and returns until it is set, and `Close-Project` skips browser tab cleanup.
    - Default: Empty.
    - More detail: [`Universal`](../../configuration-reference.md#universal-constants)
5. Are any of the shipped executable paths wrong on this machine?
    - Options: Override the individual `Universal.<App>Exe` value. Absolute paths, or placeholder paths such as `{User}\AppData\Local\...`.
    - Default: The shipped paths, which assume default install locations.
    - More detail: [`Universal`](../../configuration-reference.md#universal-constants)
6. Do you use a browser the base `Browsers` map does not list?
    - Options: Add an entry with `Exe`, `PrivateArg` and `NewWindowArg`. Because hashtables merge per key, adding one browser does not remove the others.
    - Default: The shipped five.
    - More detail: [`Universal`](../../configuration-reference.md#universal-constants)
7. Which Visual Studio solutions do you open regularly?
    - Options: One entry per solution with a `Name` and a `Solution` dot-notation reference into the expanded paths (e.g. `Projects.MyProject.Solution`), not a literal `.sln` path.
    - Default: The shipped single example.
    - More detail: [`VisualStudioSolutions`](../../configuration-reference.md#visual-studio-solutions)
8. Which folders should `Open-VSCode` offer by name?
    - Options: One entry per folder with a `Name` and a `Path` dot-notation reference into the expanded paths (e.g. `Projects.MyProject.Root`), not a literal folder path.
    - Default: The shipped two examples.
    - More detail: [`VSCodeProjects`](../../configuration-reference.md#vs-code-projects)
9. Where do this project's root folder and solution file live?
    - Options: A `PathTemplates.Projects.<Name>` sub-hashtable with `Root` and, for a Visual Studio project, `Solution`. Placeholders allowed. These are the paths the dot-notation references above resolve to.
    - Default: The shipped `Projects` map (`Self` and `ExampleProject`).
    - More detail: [`PathTemplates`](../../configuration-reference.md#path-templates--placeholder-system)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ProjectActions`, `VisualStudioSolutions`, `VSCodeProjects` - those keys are arrays, so whatever you write is the complete value.

## Steps Overview

1. Set `ProjectActions`
2. Set `PathTemplates`
3. Set `Universal`
4. Set `VisualStudioSolutions`
5. Set `VSCodeProjects`
6. Reload and confirm the merge landed

## Step 1: Set `ProjectActions`

Every project `Open-Project` offers, in menu order: one single-key hashtable per project, whose value is an ordered array of `@{ Action; Parameters }` entries, where `Action` is any exported function name. `Close-Project` reads the same list to work out what to close: `Open-VisualStudio` (`Solution`) and `Open-VSCode` (`Folder`) actions name the windows, and an `Open-ProjectTerminals-Or-RunProject`, `Open-ProjectTerminals` or `Run-Project` action makes it close the project's terminal tabs.

```powershell
ProjectActions = @(
    @{ MyProject = @(
            @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
            @{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }
        )
    }
)
```

## Step 2: Set `PathTemplates`

The per-project paths under `PathTemplates.Projects` that the `VisualStudioSolutions` and `VSCodeProjects` references resolve to. `PathTemplates` is a hashtable, so adding a project here leaves the shipped ones alone.

```powershell
PathTemplates = @{
    Projects = @{
        MyProject = @{
            Root     = "{Dev}\MyProject"
            Solution = "{Dev}\MyProject\MyProject.sln"
        }
    }
}
```

## Step 3: Set `Universal`

Machine-independent constants: executable paths (`FirefoxExe`, `DockerExe`, `DbeaverExe`, ...), the `Browsers` map, `DefaultBrowser`, shared URLs, the `TerminateProcessNames` and `VisibleWindowExclusions` lists, and `Desktop` (auto-resolved at load). Expanded in place by `Load-PathConfiguration`, so placeholders work here too.

```powershell
Universal = @{
    DefaultBrowser = "Firefox"
    Browsers = @{
        Vivaldi = @{
            Exe          = "{User}\AppData\Local\Vivaldi\Application\vivaldi.exe"
            PrivateArg   = "--incognito"
            NewWindowArg = "--new-window"
        }
    }
}
```

## Step 4: Set `VisualStudioSolutions`

The solutions `Open-VisualStudio` offers. `Solution` is a dot-notation reference into the expanded paths, not a literal `.sln` path.

```powershell
VisualStudioSolutions = @(
    @{ Name = "MyProject"; Solution = "Projects.MyProject.Solution" }
)
```

## Step 5: Set `VSCodeProjects`

The folders `Open-VSCode` offers by name. `Path` is a dot-notation reference into the expanded paths, not a literal folder path.

```powershell
VSCodeProjects = @(
    @{ Name = "WinuX"; Path = "Projects.Self.Root" }
    @{ Name = "MyProject"; Path = "Projects.MyProject.Root" }
)
```

## Step 6: Reload and confirm the merge landed

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
$global:Configuration.Universal
$global:Configuration.VisualStudioSolutions
$global:Configuration.VSCodeProjects
$global:Configuration.ProjectActions | Where-Object { $_.Keys -contains "MyProject" }
$global:MachineSpecificPaths.Projects.MyProject
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    ProjectActions = @(
        @{ MyProject = @(
                @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
                @{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }
            )
        }
    )
    PathTemplates = @{
        Projects = @{
            MyProject = @{
                Root     = "{Dev}\MyProject"
                Solution = "{Dev}\MyProject\MyProject.sln"
            }
        }
    }
    Universal = @{
        DefaultBrowser = "Firefox"
        Browsers = @{
            Vivaldi = @{
                Exe          = "{User}\AppData\Local\Vivaldi\Application\vivaldi.exe"
                PrivateArg   = "--incognito"
                NewWindowArg = "--new-window"
            }
        }
    }
    VisualStudioSolutions = @(
        @{ Name = "MyProject"; Solution = "Projects.MyProject.Solution" }
    )
    VSCodeProjects = @(
        @{ Name = "WinuX"; Path = "Projects.Self.Root" }
        @{ Name = "MyProject"; Path = "Projects.MyProject.Root" }
    )
}
```

## Related

- [`Close-Project` in the Workflow module reference](../../../modules/workflow.md#close-project) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [`Add-Project`](../configuration/Add-Project.md) - reads the same configuration
- [`Open-Project`](Open-Project.md) - reads the same configuration
- [`Open-Browser`](../application/Open-Browser.md) - reads the same configuration
- [`Open-LeagueOfLegends`](../application/Open-LeagueOfLegends.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
