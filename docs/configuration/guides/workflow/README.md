# Workflow Module Configuration Guides

One configuration guide per exported function of the `Workflow` module, which covers workspaces and projects - what an open actually opens, what a close closes, terminals, Docker stacks, and the Swagger helpers.

The [Workflow module reference](../../../modules/workflow.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Close-Project` | `ProjectActions`, `Projects`, `Universal`, `VisualStudioSolutions`, `VSCodeProjects` | [Close-Project](Close-Project.md) |
| `Docker-Cleanup` | `DockerCleanupActions` | [Docker-Cleanup](Docker-Cleanup.md) |
| `DockerWizard` | `DockerTimeouts` | [DockerWizard](DockerWizard.md) |
| `Get-SwaggerCloseTitlePatterns` | `BrowserGroups` | [Get-SwaggerCloseTitlePatterns](Get-SwaggerCloseTitlePatterns.md) |
| `Get-WorkspaceOpenDelta` | `Universal` | [Get-WorkspaceOpenDelta](Get-WorkspaceOpenDelta.md) |
| `Open-DnD` | `CampaignResources`, `Campaigns` | [Open-DnD](Open-DnD.md) |
| `Open-Project` | `ProjectActions`, `Projects` | [Open-Project](Open-Project.md) |
| `Open-ProjectTerminals` | `DefaultWSLDistribution`, `ProjectTerminals` | [Open-ProjectTerminals](Open-ProjectTerminals.md) |
| `Open-Training` | `Universal` | [Open-Training](Open-Training.md) |
| `Open-Workspace` | `DefaultVSCodeWorkspaces`, `DefaultWorkspace`, `ProjectTerminals`, `WorkspaceActions`, `Workspaces` | [Open-Workspace](Open-Workspace.md) |
| `Resolve-ProjectDockerCompose` | `DockerComposeFiles`, `ProjectTerminals`, `RunnableProjectMappings` | [Resolve-ProjectDockerCompose](Resolve-ProjectDockerCompose.md) |
| `Resolve-SwaggerBrowserGroup` | `BrowserGroupMatching`, `BrowserGroups`, `Universal` | [Resolve-SwaggerBrowserGroup](Resolve-SwaggerBrowserGroup.md) |
| `Start-Containers` | `DockerComposeFiles` | [Start-Containers](Start-Containers.md) |

## Task Guides

Longer walkthroughs that cut across several functions and keys.

- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[Close-BrowserTabsByPattern](Close-BrowserTabsByPattern.md), [Close-ProjectTerminals](Close-ProjectTerminals.md), [Close-Workspace](Close-Workspace.md), [EfCoreMigrationWizard](EfCoreMigrationWizard.md), [Focus-TerminalTab](Focus-TerminalTab.md), [Format-WorkspaceStateContent](Format-WorkspaceStateContent.md), [Get-WorkspaceBenchmark](Get-WorkspaceBenchmark.md), [Get-WorkspaceBenchmarkPath](Get-WorkspaceBenchmarkPath.md), [Get-WorkspaceOpenProtection](Get-WorkspaceOpenProtection.md), [Get-WorkspaceState](Get-WorkspaceState.md), [Get-WorkspaceStatePath](Get-WorkspaceStatePath.md), [Open-ProjectSwagger](Open-ProjectSwagger.md), [Save-WorkspaceState](Save-WorkspaceState.md), [Test-TerminalTabsAlreadyOpen](Test-TerminalTabsAlreadyOpen.md), [Training-Backup](Training-Backup.md), [Write-WorkspaceBenchmark](Write-WorkspaceBenchmark.md)

## Related

- [Workflow module reference](../../../modules/workflow.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module
