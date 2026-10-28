# Resolve-ProjectDockerCompose

The single place that knows which Docker Compose source a runnable project's database containers come from.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DockerComposeFiles`](../../configuration-reference.md#docker-compose-files) | hashtable of stack name to compose file | `@{ PostgreSQL = "docker-compose.postgresql.yml" }` | The Docker Compose stacks `Start-Containers` and `Resolve-ProjectDockerCompose` know. A relative value resolves under `MachineSpecificPaths.DockerDirectory`; an absolute path is used as-is, so non-database stacks can be registered too. |
| [`ProjectTerminals`](../../configuration-reference.md#project-terminals) | array of `@{ Name; BasePath; Paths }` | array of 3 | Here only the project's `BasePath`: on the project-local branch its `Root` in `MachineSpecificPaths` is the directory holding the project's own compose file. |
| [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings) | array of `@{ Name; Commands; DatabaseProviders; UsesDocker }` | array of 2 | Per-project run details `Run-Project` and `Resolve-ProjectDockerCompose` need: which database providers a project uses, whether it needs Docker, and how its servers start. |

## Decisions

1. Which Compose stacks should WinuX be able to start?
    - Options: Stack name to compose filename. Relative to the Docker directory, or absolute.
    - Default: The shipped `PostgreSQL` entry.
    - More detail: [`DockerComposeFiles`](../../configuration-reference.md#docker-compose-files)
2. With one entry `Start-Containers` is a pure on/off switch and with several it shows a multi-select menu. Do you want more than one?
    - Options: Add an entry per stack.
    - Default: One entry.
    - More detail: [`DockerComposeFiles`](../../configuration-reference.md#docker-compose-files)
3. Where does a project with its own compose file live?
    - Options: Its `ProjectTerminals` entry's `BasePath` - a dot-notation path whose `Root` in `MachineSpecificPaths` is the project root holding the compose file.
    - Default: The shipped three entries.
    - More detail: [`ProjectTerminals`](../../configuration-reference.md#project-terminals)
4. How does this project run?
    - Options: One entry per runnable project. `DatabaseProviders` and `UsesDocker` are what pull the Docker step in - declare them only if the project really needs containers.
    - Default: The shipped two entries.
    - More detail: [`RunnableProjectMappings`](../../configuration-reference.md#runnable-project-mappings)
5. Does the project have its own compose file, or does it use a centralized stack?
    - Options: Its own file lives at the project root (`compose.yaml`, `compose.yml`, `docker-compose.yaml` or `docker-compose.yml`, probed in that order) - set `UsesDocker = $true` on the mapping. A centralized stack is a `DockerComposeFiles` entry named after one of the mapping's `DatabaseProviders`.
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

`Resolve-ProjectDockerCompose` reads only the project's `BasePath` from it, and only on the project-local branch: the `Root` under that dot-notation path in `$global:MachineSpecificPaths` is the directory holding the project's own compose file. An entry without a `BasePath`, or one whose `Root` does not resolve, is an error.

```powershell
ProjectTerminals = @(
    @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("API", "UI") }
)
```

## Step 3: Set `RunnableProjectMappings`

Per-project run details `Run-Project` and `Resolve-ProjectDockerCompose` need: which database providers a project uses, whether it needs Docker, and how its servers start.

```powershell
RunnableProjectMappings = @(
    @{ Name = "MyProject"; Commands = @{ API = "dnr" }; DatabaseProviders = @("PostgreSQL") }
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
        @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("API", "UI") }
    )
    RunnableProjectMappings = @(
        @{ Name = "MyProject"; Commands = @{ API = "dnr" }; DatabaseProviders = @("PostgreSQL") }
    )
}
```

## Related

- [`Resolve-ProjectDockerCompose` in the Workflow module reference](../../../modules/workflow.md#resolve-projectdockercompose) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [`Resolve-DockerComposeStackPath`](Resolve-DockerComposeStackPath.md) - resolves the `DockerComposeFiles` entry this function hands to `DockerWizard`
- [`Start-Containers`](Start-Containers.md) - reads the same configuration
- [`Add-Project`](../configuration/Add-Project.md) - reads the same configuration
- [`Resolve-ProjectPath`](../helper/Resolve-ProjectPath.md) - reads the same configuration
- [`Run-Project`](../helper/Run-Project.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
