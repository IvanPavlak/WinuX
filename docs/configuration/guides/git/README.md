# Git Module Configuration Guides

One configuration guide per exported function of the `Git` module, which covers Git installation, identity, and repository-group operations. 11 functions in total: 2 read configuration and 9 do not.

The [Git module reference](../../../modules/git.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Install-Git` | `GitConfig` | [Install-Git](Install-Git.md) |
| `Update-Repositories` | `RepositoryGroups` | [Update-Repositories](Update-Repositories.md) |

## Task Guides

Longer walkthroughs that cut across several functions and keys.

- [Add New Repository](add-new-repository.md) - repository groups and what `Update-Repositories` walks

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[Git-Diff](Git-Diff.md), [Git-Obsidian](Git-Obsidian.md), [GitBranch](GitBranch.md), [GitBranchDeleteAndPrune](GitBranchDeleteAndPrune.md), [GitMergeM](GitMergeM.md), [GitPull](GitPull.md), [GitStatus](GitStatus.md), [GitSwitch](GitSwitch.md), [Initialize-Repository](Initialize-Repository.md)

## Related

- [Git module reference](../../../modules/git.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module
