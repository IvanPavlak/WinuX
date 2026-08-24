# Run-Project

Opens Windows Terminal tabs for one or more configured runnable projects. Alias: `rp`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`ProjectTerminals`](../../configuration-reference.md#project-terminals) | array of `@{ Project; Tabs; ... }` | array of 3 | Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and with what titles and starting directories. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable. |
| [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings) | array of `@{ Project; ... }` | array of 2 | Per-project run details `Run-Project` and `Resolve-ProjectDockerCompose` need: which database providers a project uses, whether it needs Docker, and how its servers start. |
| [`RunnableProjects`](../../configuration-reference.md#runnable-project-mappings) | array of project names | `@("WinuX", "ExampleProject")` | Which projects `Run-Project` offers. |

## Decisions

1. Which terminal tabs should open for this project?
    - Options: One entry per project with its tab list. Each tab can set a title and a starting directory, and can run in WSL.
    - Default: The shipped three entries.
    - More detail: [`ProjectTerminals`](../../configuration-reference.md#project-terminals)
2. How does this project run?
    - Options: One entry per runnable project. `DatabaseProviders` and `UsesDocker` are what pull the Docker step in - declare them only if the project really needs containers.
    - Default: The shipped two entries.
    - More detail: [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings)
3. Does the project have its own `docker-compose.yml`, or does it use a centralized stack?
    - Options: Its own file lives at the project root; a centralized stack is a `DockerComposeFiles` entry.
    - Default: Centralized.
    - More detail: [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings)
4. Which projects should `Run-Project` offer?
    - Options: One name per runnable project. Needs a matching `RunnableProjectMappings` entry.
    - Default: The shipped two.
    - More detail: [`RunnableProjects`](../../configuration-reference.md#runnable-project-mappings)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ProjectTerminals`, `RunnableProjectMappings`, `RunnableProjects` - those keys are arrays, so whatever you write is the complete value.

## Steps Overview

1. Set `ProjectTerminals`
2. Set `RunnableProjectMappings`
3. Set `RunnableProjects`
4. Reload and confirm the merge landed

## Step 1: Set `ProjectTerminals`

Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and with what titles and starting directories. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable.

```powershell
ProjectTerminals = @(
    @{ Project = "MyProject"; Tabs = @(
        @{ Title = "MyProject"; Path = "{Dev}\MyProject" }
    )}
)
```

## Step 2: Set `RunnableProjectMappings`

Per-project run details `Run-Project` and `Resolve-ProjectDockerCompose` need: which database providers a project uses, whether it needs Docker, and how its servers start.

```powershell
RunnableProjectMappings = @(
    @{ Project = "MyProject"; DatabaseProviders = @("PostgreSQL") }
)
```

## Step 3: Set `RunnableProjects`

Which projects `Run-Project` offers.

```powershell
RunnableProjects = @("MyProject")
```

## Step 4: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.ProjectTerminals
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.ProjectTerminals
$global:Configuration.RunnableProjectMappings
$global:Configuration.RunnableProjects
$global:Configuration.RunnableProjects
Resolve-RunProjectSteps | Format-Table
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    ProjectTerminals = @(
        @{ Project = "MyProject"; Tabs = @(
            @{ Title = "MyProject"; Path = "{Dev}\MyProject" }
        )}
    )
    RunnableProjectMappings = @(
        @{ Project = "MyProject"; DatabaseProviders = @("PostgreSQL") }
    )
    RunnableProjects = @("MyProject")
}
```

## Related

- [`Run-Project` in the Helper module reference](../../../modules/helper.md#run-project) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [`Add-Project`](../configuration/Add-Project.md) - reads the same configuration
- [`Resolve-ProjectPath`](Resolve-ProjectPath.md) - reads the same configuration
- [`Open-ProjectTerminals`](../workflow/Open-ProjectTerminals.md) - reads the same configuration
- [`Open-Workspace`](../workflow/Open-Workspace.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
