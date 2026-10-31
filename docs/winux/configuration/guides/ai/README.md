# AI Module Configuration Guides

One configuration guide per exported function of the `AI` module, which covers machine-global AI coding agent setup: one generic mechanism that vendors the AI artifacts (skills, mods, rules, prompts and agents) and deploys them into the AI apps a machine uses, on Windows and in WSL, plus Claude Code plugin marketplace registration and the MCP servers of Claude Code and Codex.

The [AI module reference](../../../modules/ai.md) is the authority on what each function *does*. These guides cover what to *configure* for it. The design is on [AI Artifacts](../../../ai/artifacts.md).

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Deploy-AiArtifacts` | `AiArtifacts` (incl. `Checkouts`, `Manifests`), `AiHarnesses`, `AiProfiles`, `BootstrapConfig.Steps.AiArtifacts`, `DefaultWSLDistribution`, `DefaultWSLUsername` | [Deploy-AiArtifacts](Deploy-AiArtifacts.md) |
| `Deploy-AiMarketplaces` | `AiMarketplaces`, `AiProfiles`, `BootstrapConfig.Steps.AiMarketplaces`, `DefaultWSLDistribution`, `DefaultWSLUsername` | [Deploy-AiMarketplaces](Deploy-AiMarketplaces.md) |
| `Deploy-AiMcpServers` | `AiMcpServers`, `AiProfiles`, `BootstrapConfig.Steps.AiMcpServers`, `DefaultWSLDistribution`, `DefaultWSLUsername`, `ValidMachineTypes` | [Deploy-AiMcpServers](Deploy-AiMcpServers.md) |
| `Get-AiArtifactPlan` | `AiArtifacts.Deploy`, `AiArtifacts.Use`, `AiHarnesses`, `RepositoryGroups` | [Get-AiArtifactPlan](Get-AiArtifactPlan.md) |
| `Get-AiArtifactRoster` | `AiArtifacts.Root`, `AiArtifacts.Sources`, `AiArtifacts.Checkouts`, `AiArtifacts.Manifests`, `AiArtifacts.Exclude`, `AiProfiles` | [Get-AiArtifactRoster](Get-AiArtifactRoster.md) |
| `Initialize-AiProfile` | `AiProfiles`, `AiMcpServers.Servers`, `BootstrapConfig.Steps.AiProfileInit` | [Initialize-AiProfile](Initialize-AiProfile.md) |
| `List-AiArtifacts` | `AiArtifacts`, `AiHarnesses`, `AiProfiles`, `ShowFunctionDetailsColors` | [List-AiArtifacts](List-AiArtifacts.md) |
| `Resolve-AiArtifactsConfig` | `AiArtifacts`, `AiHarnesses`, `AiProfiles`, `BasePaths`, `DefaultWSLUsername` | [Resolve-AiArtifactsConfig](Resolve-AiArtifactsConfig.md) |
| `Resolve-AiProfile` | `AiProfiles` | [Resolve-AiProfile](Resolve-AiProfile.md) |
| `Test-AiProfile` | `AiProfiles`, `AiHarnesses`, `AiMcpServers.Servers` | [Test-AiProfile](Test-AiProfile.md) |
| `Update-AiArtifacts` | `AiArtifacts.Sources`, `AiArtifacts.Manifests`, `AiArtifacts.Root` | [Update-AiArtifacts](Update-AiArtifacts.md) |

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[ConvertTo-AiManagedSettings](ConvertTo-AiManagedSettings.md), [Deploy-AiManagedSettings](Deploy-AiManagedSettings.md), [Get-AiArtifactManifest](Get-AiArtifactManifest.md), [Get-AiSkillDescription](Get-AiSkillDescription.md), [Get-AiSkillManifest](Get-AiSkillManifest.md), [Resolve-AiModsPluginDirs](Resolve-AiModsPluginDirs.md), [Set-ClaudeSettingsEnv](Set-ClaudeSettingsEnv.md), [Set-ClaudeSettingsKey](Set-ClaudeSettingsKey.md), [Sync-AiManifestCache](Sync-AiManifestCache.md), [Test-AiModsCli](Test-AiModsCli.md)

## Related

- [AI module reference](../../../modules/ai.md) - what each function does
- [AI Artifacts](../../../ai/artifacts.md) - the design
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module
