# Workflow Module Configuration Guides

One configuration guide per exported function of the `Workflow` module, which covers workspaces and projects - what an open actually opens, what a close closes, terminals, Docker stacks, the Swagger helpers, and the startup tasks a machine runs on its own at sign-in, unlock, wake or when a terminal opens.

The [Workflow module reference](../../../modules/workflow.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Close-Project` | `PathTemplates`, `ProjectActions`, `Universal`, `VisualStudioSolutions`, `VSCodeProjects` | [Close-Project](Close-Project.md) |
| `Docker-Cleanup` | `DockerCleanupActions`, `DockerCleanupStartMode` | [Docker-Cleanup](Docker-Cleanup.md) |
| `DockerWizard` | `DockerTimeouts` | [DockerWizard](DockerWizard.md) |
| `Get-StartupTaskDefinitions` | `Startup.Tasks`, `Startup.Conditions`, `RepositoryUpdate.Startup` (deprecated) | [Get-StartupTaskDefinitions](Get-StartupTaskDefinitions.md) |
| `Get-SwaggerCloseTitlePatterns` | `BrowserGroups` | [Get-SwaggerCloseTitlePatterns](Get-SwaggerCloseTitlePatterns.md) |
| `Get-WorkspaceOpenDelta` | `Universal` | [Get-WorkspaceOpenDelta](Get-WorkspaceOpenDelta.md) |
| `Invoke-StartupTask` | `Startup.Tasks` (by `-Name`), `Startup.Conditions` | [Invoke-StartupTask](Invoke-StartupTask.md) |
| `Invoke-StartupTasks` | `Startup` (`Tasks`, `Conditions`, `FailureReport`) - the startup tasks walkthrough | [Invoke-StartupTasks](Invoke-StartupTasks.md) |
| `Measure-WorkspaceOpen` | `FancyZonesApplyMethod`, `WorkspaceActions`, `WorkspaceBenchmark`, `WorkspaceLayoutPipelining`, `WorkspaceLayoutPrepareEarly` | [Measure-WorkspaceOpen](Measure-WorkspaceOpen.md) |
| `Open-DnD` | `CampaignResources` | [Open-DnD](Open-DnD.md) |
| `Open-Project` | `ProjectActions` | [Open-Project](Open-Project.md) |
| `Open-ProjectTerminals` | `DefaultWSLDistribution`, `ProjectTerminals`, `TerminalGreeting` | [Open-ProjectTerminals](Open-ProjectTerminals.md) |
| `Open-Training` | `PathTemplates`, `Universal` | [Open-Training](Open-Training.md) |
| `Open-Workspace` | `DefaultVSCodeWorkspaces`, `DefaultWorkspace`, `ProjectActions`, `ProjectTerminals`, `WorkspaceActions` (incl. the `Machine` / `LayoutMachine` / `Project` scopes and `MachineParameters` / `LayoutMachineParameters` / `ProjectParameters` tables), `WorkspaceBenchmark`, `WorkspaceLayoutPrepareEarly`, `WorkspaceTemplates` | [Open-Workspace](Open-Workspace.md) |
| `Resolve-DockerComposeStackPath` | `DockerComposeFiles`, `PathTemplates` | [Resolve-DockerComposeStackPath](Resolve-DockerComposeStackPath.md) |
| `Resolve-ProjectDockerCompose` | `DockerComposeFiles`, `ProjectTerminals`, `RunnableProjectMappings` | [Resolve-ProjectDockerCompose](Resolve-ProjectDockerCompose.md) |
| `Resolve-SwaggerBrowserGroup` | `BrowserGroupMatching`, `BrowserGroups`, `Universal` | [Resolve-SwaggerBrowserGroup](Resolve-SwaggerBrowserGroup.md) |
| `Resolve-WorkspaceActions` | `LayoutMachineTypeOverrides`, `ProjectActions`, `SmallDisplayMachineType`, `ValidMachineTypes`, `WorkspaceActions` | [Resolve-WorkspaceActions](Resolve-WorkspaceActions.md) |
| `Start-Containers` | `DockerComposeFiles` | [Start-Containers](Start-Containers.md) |
| `Test-StartupCondition` | `Startup.Conditions` | [Test-StartupCondition](Test-StartupCondition.md) |

## Task Guides

Longer walkthroughs that cut across several functions and keys.

- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[Close-BrowserTabsByPattern](Close-BrowserTabsByPattern.md), [Close-ProjectTerminals](Close-ProjectTerminals.md), [Close-Workspace](Close-Workspace.md), [ConvertTo-WorkspaceOpenSummary](ConvertTo-WorkspaceOpenSummary.md), [EfCoreMigrationWizard](EfCoreMigrationWizard.md), [Focus-TerminalTab](Focus-TerminalTab.md), [Format-WorkspaceStateContent](Format-WorkspaceStateContent.md), [Get-WorkspaceBenchmark](Get-WorkspaceBenchmark.md), [Get-WorkspaceBenchmarkPath](Get-WorkspaceBenchmarkPath.md), [Get-WorkspaceOpenMeasurement](Get-WorkspaceOpenMeasurement.md), [Get-WorkspaceOpenMeasurementPath](Get-WorkspaceOpenMeasurementPath.md), [Get-WorkspaceOpenProtection](Get-WorkspaceOpenProtection.md), [Get-WorkspaceState](Get-WorkspaceState.md), [Get-WorkspaceStatePath](Get-WorkspaceStatePath.md), [Invoke-StartupTaskPromptCheck](Invoke-StartupTaskPromptCheck.md), [New-StartupTaskShellCommand](New-StartupTaskShellCommand.md), [Open-ProjectSwagger](Open-ProjectSwagger.md), [Read-WorkspaceBenchmark](Read-WorkspaceBenchmark.md), [Read-WorkspaceOpenMeasurement](Read-WorkspaceOpenMeasurement.md), [Register-StartupTaskPromptCheck](Register-StartupTaskPromptCheck.md), [Resolve-TrackedWorkspaceWindow](Resolve-TrackedWorkspaceWindow.md), [Save-WorkspaceState](Save-WorkspaceState.md), [Start-StartupTaskShell](Start-StartupTaskShell.md), [Test-StartupTaskDue](Test-StartupTaskDue.md), [Test-TerminalTabsAlreadyOpen](Test-TerminalTabsAlreadyOpen.md), [Training-Backup](Training-Backup.md), [Wait-StartupTaskResult](Wait-StartupTaskResult.md), [Write-WorkspaceBenchmark](Write-WorkspaceBenchmark.md)

## Related

- [Workflow module reference](../../../modules/workflow.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module
