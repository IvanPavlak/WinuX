# Helper Module Configuration Guides

One configuration guide per exported function of the `Helper` module, which covers the shared utilities everything else is built from: selection prompts, path and step resolution, retries, .NET and EF Core helpers, and the function reference tooling.

The [Helper module reference](../../../modules/helper.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Backup-RepositoryItem` | `Backups.Retention` | [Backup-RepositoryItem](Backup-RepositoryItem.md) |
| `Clear-OldBackups` | `Backups.Retention` | [Clear-OldBackups](Clear-OldBackups.md) |
| `Confirm-ConfigValue` | caller-supplied | [Confirm-ConfigValue](Confirm-ConfigValue.md) |
| `Invoke-GoogleTranslate` | `DefaultTranslateLanguages` | [Invoke-GoogleTranslate](Invoke-GoogleTranslate.md) |
| `List-Functions` | `FunctionDiscrepancyExclusions`, `ListFunctionsColors` | [List-Functions](List-Functions.md) |
| `Loading-Spinner` | `DefaultSpinner`, `LoadingSpinners` | [Loading-Spinner](Loading-Spinner.md) |
| `Preview-LoadingSpinners` | `LoadingSpinners` | [Preview-LoadingSpinners](Preview-LoadingSpinners.md) |
| `Resolve-ConfigPathValue` | caller-supplied | [Resolve-ConfigPathValue](Resolve-ConfigPathValue.md) |
| `Resolve-ProjectPath` | `ProjectTerminals`, `RepositoryGroups`, `Universal` | [Resolve-ProjectPath](Resolve-ProjectPath.md) |
| `Resolve-RunProjectSteps` | `RunProject` | [Resolve-RunProjectSteps](Resolve-RunProjectSteps.md) |
| `Run-Project` | `ProjectTerminals`, `RunnableProjectMappings`, `RunnableProjects` | [Run-Project](Run-Project.md) |
| `Show-FunctionDetails` | `ShowFunctionDetailsColors` | [Show-FunctionDetails](Show-FunctionDetails.md) |
| `Test-ConfigValue` | caller-supplied | [Test-ConfigValue](Test-ConfigValue.md) |
| `Test-WSLDistributionInstalled` | `DefaultWSLDistribution` | [Test-WSLDistributionInstalled](Test-WSLDistributionInstalled.md) |

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[BranchExists](BranchExists.md), [Cd-Desktop](Cd-Desktop.md), [Close-WindowsTerminalTab](Close-WindowsTerminalTab.md), [Collect-BrowserUrls](Collect-BrowserUrls.md), [Convert-GlobalVariablesToParameters](Convert-GlobalVariablesToParameters.md), [Countdown](Countdown.md), [Create-CenteredBorder](Create-CenteredBorder.md), [Create-Executable](Create-Executable.md), [Custom-ReadHost](Custom-ReadHost.md), [DotnetBuildAndRun](DotnetBuildAndRun.md), [DotnetPublish](DotnetPublish.md), [DotnetRun](DotnetRun.md), [Find-EfMigrationProjects](Find-EfMigrationProjects.md), [Find-EfStartupProject](Find-EfStartupProject.md), [Find-Item](Find-Item.md), [Get-DatabaseTypeFromProject](Get-DatabaseTypeFromProject.md), [Get-DbContextFromSnapshot](Get-DbContextFromSnapshot.md), [Get-DbContextsFromProject](Get-DbContextsFromProject.md), [Get-DotnetVersionFromTFM](Get-DotnetVersionFromTFM.md), [Get-EfCoreDbContexts](Get-EfCoreDbContexts.md), [Get-EfCurrentDatabaseType](Get-EfCurrentDatabaseType.md), [Get-EfMigrations](Get-EfMigrations.md), [Get-FilteredParams](Get-FilteredParams.md), [Get-PowerShellFunctionDependencies](Get-PowerShellFunctionDependencies.md), [Get-RepositoryName](Get-RepositoryName.md), [Get-RepositoryPath](Get-RepositoryPath.md), [Get-RpcRetryPolicy](Get-RpcRetryPolicy.md), [Get-TargetTerminalWindow](Get-TargetTerminalWindow.md), [Get-TerminalTabSnapshot](Get-TerminalTabSnapshot.md), [Get-WindowsTerminalTabTitles](Get-WindowsTerminalTabTitles.md), [Get-WindowTitleCandidates](Get-WindowTitleCandidates.md), [Initialize-Directory](Initialize-Directory.md), [Invoke-PrivacyRequest](Invoke-PrivacyRequest.md), [Invoke-RerunLastCommandExit](Invoke-RerunLastCommandExit.md), [Invoke-TorRequest](Invoke-TorRequest.md), [Invoke-WithOptionalRetry](Invoke-WithOptionalRetry.md), [Invoke-WithRetry](Invoke-WithRetry.md), [List-AvailableColors](List-AvailableColors.md), [NpmInstallAndStart](NpmInstallAndStart.md), [ProcessGroupRecursive](ProcessGroupRecursive.md), [Refresh-BrowserTabs](Refresh-BrowserTabs.md), [ReRun-LastCommand](ReRun-LastCommand.md), [Resolve-EfMigrationDbContext](Resolve-EfMigrationDbContext.md), [Resolve-HostingTerminalTab](Resolve-HostingTerminalTab.md), [Resolve-Selection](Resolve-Selection.md), [Resolve-Steps](Resolve-Steps.md), [Show-Image](Show-Image.md), [Test-AdminPrivileges](Test-AdminPrivileges.md), [Test-AppNotInstalled](Test-AppNotInstalled.md), [Test-HasEfCoreDesign](Test-HasEfCoreDesign.md), [Test-ManifestCompleteness](Test-ManifestCompleteness.md), [Test-PrivacyStatus](Test-PrivacyStatus.md), [Test-RegistryValue](Test-RegistryValue.md), [Test-RpcUnavailableError](Test-RpcUnavailableError.md), [Test-TcpPortReachable](Test-TcpPortReachable.md), [Test-WindowTitleCandidates](Test-WindowTitleCandidates.md), [Test-WSLEnabled](Test-WSLEnabled.md), [Write-ManualInstructionsToDesktop](Write-ManualInstructionsToDesktop.md)

## Related

- [Helper module reference](../../../modules/helper.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module
