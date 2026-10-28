# Git Module Configuration Guides

One configuration guide per exported function of the `Git` module, which covers Git installation, identity, and repository-group operations.

The [Git module reference](../../../modules/git.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Get-RepositoryUpdateStartupSettings` | `RepositoryUpdate` | [Get-RepositoryUpdateStartupSettings](Get-RepositoryUpdateStartupSettings.md) |
| `Git-Obsidian` | `PathTemplates.ObsidianDirectory`, `Obsidian.GitEndLocation` | [Git-Obsidian](Git-Obsidian.md) |
| `GitStatus` | `GitStatusArguments` | [GitStatus](GitStatus.md) |
| `Install-Git` | `GitConfig` | [Install-Git](Install-Git.md) |
| `Invoke-StartupRepositoryUpdate` | `RepositoryUpdate` | [Invoke-StartupRepositoryUpdate](Invoke-StartupRepositoryUpdate.md) |
| `Resolve-RepositoryDefaultBranch` | `RepositoryUpdate` | [Resolve-RepositoryDefaultBranch](Resolve-RepositoryDefaultBranch.md) |
| `Resolve-RepositoryTargets` | `RepositoryGroups` | [Resolve-RepositoryTargets](Resolve-RepositoryTargets.md) |
| `Update-Repositories` | `RepositoryGroups`, `RepositoryUpdate` | [Update-Repositories](Update-Repositories.md) |

## Task Guides

Longer walkthroughs that cut across several functions and keys.

- [Add New Repository](add-new-repository.md) - repository groups and what `Update-Repositories` walks

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[ConvertFrom-UpstreamManifest](ConvertFrom-UpstreamManifest.md), [Format-RepositoryUpdateResult](Format-RepositoryUpdateResult.md), [Get-RepositoryUpdateDayStart](Get-RepositoryUpdateDayStart.md), [Git-Diff](Git-Diff.md), [GitBranch](GitBranch.md), [GitBranchDeleteAndPrune](GitBranchDeleteAndPrune.md), [GitMergeM](GitMergeM.md), [GitPull](GitPull.md), [GitSwitch](GitSwitch.md), [Initialize-Repository](Initialize-Repository.md), [Invoke-RepositoryUpdatePromptCheck](Invoke-RepositoryUpdatePromptCheck.md), [Merge-Upstreams](Merge-Upstreams.md), [Register-RepositoryUpdatePromptCheck](Register-RepositoryUpdatePromptCheck.md), [Resolve-UpstreamPathClass](Resolve-UpstreamPathClass.md), [Resolve-UpstreamRemote](Resolve-UpstreamRemote.md), [Restore-RepositoryStash](Restore-RepositoryStash.md), [Set-GitConsoleColor](Set-GitConsoleColor.md), [Test-GitRepository](Test-GitRepository.md), [Test-RepositoryUpdateStampFresh](Test-RepositoryUpdateStampFresh.md), [Update-Repository](Update-Repository.md), [Update-RepositoryDefaultBranch](Update-RepositoryDefaultBranch.md)

## Related

- [Git module reference](../../../modules/git.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module
