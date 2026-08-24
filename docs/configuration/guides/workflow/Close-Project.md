# Close-Project

Closes all project-specific resources opened by `Open-Project` (Visual Studio windows, VSCode windows, Windows Terminal tabs, and browser tabs/windows), enabling fast switching between projects by closing only project-specific resources while keeping workspace-level applications running.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`ProjectActions`](../../configuration-reference.md#project-actions) | hashtable of project name to action array | hashtable, 3 keys | What `Open-Project` does for each project: an ordered array of `@{ Action; Parameters }` entries, where `Action` is any exported function name. `Close-Project` reads the same map to work out what to close. |
| [`Projects`](../../configuration-reference.md#projects-list) | array of project names | `@("WinuX", "ExampleProject", "Server")` | The project names `Open-Project` offers. A name here needs a matching `ProjectActions` entry to do anything, and usually a `PathTemplates.Projects` entry for its root. |
| [`Universal`](../../configuration-reference.md#universal-constants) | hashtable, 26 keys | hashtable, 26 keys | Machine-independent constants: executable paths (`FirefoxExe`, `DockerExe`, `DbeaverExe`, ...), the `Browsers` map, `DefaultBrowser`, shared URLs, the `ProcessCleanup` lists, and `Desktop` (auto-resolved at load). Expanded in place by `Load-PathConfiguration`, so placeholders work here too. |
| [`VisualStudioSolutions`](../../configuration-reference.md#visual-studio-solutions) | array of `@{ Name; Path }` | array of 1 | The solutions `Open-VisualStudio` offers, and what `Close-Project` closes. |
| [`VSCodeProjects`](../../configuration-reference.md#vs-code-projects) | array of `@{ Name; Path }` | array of 2 | The folders `Open-VSCode` offers by name. |

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
3. Which projects should `Open-Project` offer?
    - Options: One name per project - see [Add New Project](../workflow/add-new-project.md) for the whole walk. The array replaces wholesale, so include the shipped names you still want.
    - Default: The shipped three.
    - More detail: [`Projects`](../../configuration-reference.md#projects-list)
4. Which browser should be the default?
    - Options: A key from `Universal.Browsers`: `Firefox`, `Chrome`, `Edge`, `Brave`, `Tor`. Ships empty, so `Open-Browser` asks or uses the system default.
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
    - Options: One entry per solution with a name and a path. Placeholders allowed.
    - Default: The shipped single example.
    - More detail: [`VisualStudioSolutions`](../../configuration-reference.md#visual-studio-solutions)
8. Which folders should `Open-VSCode` offer by name?
    - Options: One entry per folder with a name and a path. Placeholders allowed.
    - Default: The shipped two examples.
    - More detail: [`VSCodeProjects`](../../configuration-reference.md#vs-code-projects)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `Projects`, `VisualStudioSolutions`, `VSCodeProjects` - those keys are arrays, so whatever you write is the complete value.

## Steps Overview

1. Set `ProjectActions`
2. Set `Projects`
3. Set `Universal`
4. Set `VisualStudioSolutions`
5. Set `VSCodeProjects`
6. Reload and confirm the merge landed

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

## Step 3: Set `Universal`

Machine-independent constants: executable paths (`FirefoxExe`, `DockerExe`, `DbeaverExe`, ...), the `Browsers` map, `DefaultBrowser`, shared URLs, the `ProcessCleanup` lists, and `Desktop` (auto-resolved at load). Expanded in place by `Load-PathConfiguration`, so placeholders work here too.

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

The solutions `Open-VisualStudio` offers, and what `Close-Project` closes.

```powershell
VisualStudioSolutions = @(
    @{ Name = "MyProject"; Path = "{Dev}\MyProject\MyProject.sln" }
)
```

## Step 5: Set `VSCodeProjects`

The folders `Open-VSCode` offers by name.

```powershell
VSCodeProjects = @(
    @{ Name = "MyProject"; Path = "{Dev}\MyProject" }
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
$global:Configuration.Projects
$global:Configuration.Universal
$global:Configuration.VisualStudioSolutions
$global:Configuration.VSCodeProjects
$global:Configuration.ProjectActions.MyProject
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
        @{ Name = "MyProject"; Path = "{Dev}\MyProject\MyProject.sln" }
    )
    VSCodeProjects = @(
        @{ Name = "MyProject"; Path = "{Dev}\MyProject" }
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
