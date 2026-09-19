# Run-Project

Opens Windows Terminal tabs for one or more configured runnable projects. Alias: `rp`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`ProjectTerminals`](../../configuration-reference.md#project-terminals) | array of `@{ Name; BasePath; Paths }` | array of 3 | Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and where each one starts. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable. |
| [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings) | array of `@{ Name; Commands; ... }` | array of 2 | Every project `Run-Project` offers, in menu order, with the command each of its terminal paths runs and which database providers it needs. |

## Decisions

1. Which terminal tabs should open for this project?
    - Options: One entry per project with its tab list. Each tab can set a title and a starting directory, and can run in WSL - a WSL tab written as `@{ Key = "WSL"; Path = "/mnt/c/Users/Me/Repo" }` starts in that directory, with the path written as WSL sees it.
    - Default: The shipped three entries.
    - More detail: [`ProjectTerminals`](../../configuration-reference.md#project-terminals)
2. Which projects should `Run-Project` offer, in what order, and how does each one run?
    - Options: One entry per runnable project, in menu order. `Commands` is keyed by the `ProjectTerminals` path the command runs in. `DatabaseProviders` and `UsesDocker` are what pull the Docker step in - declare them only if the project really needs containers.
    - Default: The shipped two entries.
    - More detail: [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings)
3. Does the project have its own compose file, or does it use a centralized stack?
    - Options: Its own file lives at the project root (`compose.yaml`, `compose.yml`, `docker-compose.yaml` or `docker-compose.yml`, probed in that order) - set `UsesDocker = $true` on the mapping. A centralized stack is a `DockerComposeFiles` entry named after one of the mapping's `DatabaseProviders`.
    - Default: Centralized.
    - More detail: [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ProjectTerminals` and `RunnableProjectMappings` - those keys are arrays, so whatever you write is the complete value.

## Steps Overview

1. Set `ProjectTerminals`
2. Set `RunnableProjectMappings`
3. Reload and confirm the merge landed

## Step 1: Set `ProjectTerminals`

Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and where each one starts. `Paths` names keys under the project's `PathTemplates` entry; `ROOT` is the project root. `Run-Project` opens the same tabs from the same list, so a tab configured here is a tab both `op` and `rp` give you.

```powershell
ProjectTerminals = @(
    @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("API", "UI") }
)
```

A tab can also be a WSL tab, written as `@{ Key = "WSL"; Path = "/mnt/c/Users/Me/Development/MyProject" }` - the path as WSL sees it, so the tab starts in the project instead of the distribution's home. That tab runs the distribution's shell, not PowerShell: `Run-Project` opens it and runs nothing in it, and a command written against a `WSL` key in `RunnableProjectMappings` is reported and skipped. Every entry shape `Paths` accepts is listed under [`ProjectTerminals`](../../configuration-reference.md#project-terminals).

## Step 2: Set `RunnableProjectMappings`

Every project `Run-Project` offers, in the order the menu offers them - this list is the only definition of a runnable project. `Commands` is keyed by the `ProjectTerminals` path the command runs in, so a command sits next to the path it belongs to; a path with no command listed just gets its terminal tab.

```powershell
RunnableProjectMappings = @(
    @{ Name              = "MyProject";
        Commands          = @{ API = "dnr"; UI = "nir" };
        DatabaseProviders = @("PostgreSQL");
    }
)
```

## Step 3: Reload and confirm the merge landed

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
$global:Configuration.RunnableProjectMappings.Name
Resolve-RunProjectSteps | Format-Table
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    ProjectTerminals = @(
        @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("API", "UI") }
    )
    RunnableProjectMappings = @(
        @{ Name              = "MyProject";
            Commands          = @{ API = "dnr"; UI = "nir" };
            DatabaseProviders = @("PostgreSQL");
        }
    )
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
