# Resolve-ProjectDockerCompose

The single place that knows which Docker Compose source a runnable project's database containers come from.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DockerComposeFiles`](../../configuration-reference.md#more-sections-quick-reference) | hashtable of stack name to compose file | `@{ PostgreSQL = "docker-compose.postgresql.yml" }` | The Docker Compose stacks `Start-Containers` and `Resolve-ProjectDockerCompose` know. A relative value resolves under `MachineSpecificPaths.DockerDirectory`; an absolute path is used as-is, so non-database stacks can be registered too. |
| [`ProjectTerminals`](../../configuration-reference.md#project-terminals) | array of `@{ Project; Tabs; ... }` | array of 3 | Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and with what titles and starting directories. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable. |
| [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings) | array of `@{ Project; ... }` | array of 2 | Per-project run details `Run-Project` and `Resolve-ProjectDockerCompose` need: which database providers a project uses, whether it needs Docker, and how its servers start. |

## Decisions

1. Which Compose stacks should WinuX be able to start?
    - Options: Stack name to compose filename. Relative to the Docker directory, or absolute.
    - Default: The shipped `PostgreSQL` entry.
    - More detail: [`DockerComposeFiles`](../../configuration-reference.md#more-sections-quick-reference)
2. With one entry `Start-Containers` is a pure on/off switch and with several it shows a multi-select menu. Do you want more than one?
    - Options: Add an entry per stack.
    - Default: One entry.
    - More detail: [`DockerComposeFiles`](../../configuration-reference.md#more-sections-quick-reference)
3. Which terminal tabs should open for this project?
    - Options: One entry per project with its tab list. Each tab can set a title and a starting directory, and can run in WSL.
    - Default: The shipped three entries.
    - More detail: [`ProjectTerminals`](../../configuration-reference.md#project-terminals)
4. How does this project run?
    - Options: One entry per runnable project. `DatabaseProviders` and `UsesDocker` are what pull the Docker step in - declare them only if the project really needs containers.
    - Default: The shipped two entries.
    - More detail: [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings)
5. Does the project have its own `docker-compose.yml`, or does it use a centralized stack?
    - Options: Its own file lives at the project root; a centralized stack is a `DockerComposeFiles` entry.
    - Default: Centralized.
    - More detail: [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ProjectTerminals`, `RunnableProjectMappings` - those keys are arrays, so whatever you write is the complete value.

## Steps Overview

1. Set `DockerComposeFiles`
2. Set `ProjectTerminals`
3. Set `RunnableProjectMappings`
4. Reload and confirm the merge landed

## Step 1: Set `DockerComposeFiles`

The Docker Compose stacks `Start-Containers` and `Resolve-ProjectDockerCompose` know. A relative value resolves under `MachineSpecificPaths.DockerDirectory`; an absolute path is used as-is, so non-database stacks can be registered too.

```powershell
DockerComposeFiles = @{
    PostgreSQL = "docker-compose.postgresql.yml"
}
```

## Step 2: Set `ProjectTerminals`

Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and with what titles and starting directories. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable.

```powershell
ProjectTerminals = @(
    @{ Project = "MyProject"; Tabs = @(
        @{ Title = "MyProject"; Path = "{Dev}\MyProject" }
    )}
)
```

## Step 3: Set `RunnableProjectMappings`

Per-project run details `Run-Project` and `Resolve-ProjectDockerCompose` need: which database providers a project uses, whether it needs Docker, and how its servers start.

```powershell
RunnableProjectMappings = @(
    @{ Project = "MyProject"; DatabaseProviders = @("PostgreSQL") }
)
```

## Step 4: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.DockerComposeFiles
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DockerComposeFiles
$global:Configuration.ProjectTerminals
$global:Configuration.RunnableProjectMappings
Resolve-ProjectDockerCompose -ProjectName "MyProject"
$global:Configuration.DockerComposeFiles
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DockerComposeFiles = @{
        PostgreSQL = "docker-compose.postgresql.yml"
    }
    ProjectTerminals = @(
        @{ Project = "MyProject"; Tabs = @(
            @{ Title = "MyProject"; Path = "{Dev}\MyProject" }
        )}
    )
    RunnableProjectMappings = @(
        @{ Project = "MyProject"; DatabaseProviders = @("PostgreSQL") }
    )
}
```

## Related

- [`Resolve-ProjectDockerCompose` in the Workflow module reference](../../../modules/workflow.md#resolve-projectdockercompose) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [`Start-Containers`](Start-Containers.md) - reads the same configuration
- [`Add-Project`](../configuration/Add-Project.md) - reads the same configuration
- [`Resolve-ProjectPath`](../helper/Resolve-ProjectPath.md) - reads the same configuration
- [`Run-Project`](../helper/Run-Project.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
