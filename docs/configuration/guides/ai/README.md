# AI Module Configuration Guides

One configuration guide per exported function of the `AI` module, which covers machine-global AI coding agent setup: one generic mechanism that vendors the AI artifacts (skills, mods, rules, prompts and agents) and deploys them into the AI apps a machine uses, on Windows and in WSL, plus Claude Code plugin marketplace registration and the MCP servers of Claude Code and Codex.

The [AI module reference](../../../modules/ai.md) is the authority on what each function *does*. These guides cover what to *configure* for it. The design is on [AI Artifacts](../../../ai/artifacts.md).

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Deploy-AiArtifacts` | `AiArtifacts`, `AiHarnesses`, `BootstrapConfig.Steps.AiArtifacts`, `DefaultWSLDistribution`, `DefaultWSLUsername` | [Deploy-AiArtifacts](Deploy-AiArtifacts.md) |
| `Deploy-AiMarketplaces` | `AiMarketplaces`, `BootstrapConfig.Steps.AiMarketplaces`, `DefaultWSLDistribution`, `DefaultWSLUsername` | [Deploy-AiMarketplaces](Deploy-AiMarketplaces.md) |
| `Deploy-AiMcpServers` | `AiMcpServers`, `BootstrapConfig.Steps.AiMcpServers`, `DefaultWSLDistribution`, `DefaultWSLUsername`, `ValidMachineTypes` | [Deploy-AiMcpServers](Deploy-AiMcpServers.md) |
| `Get-AiArtifactPlan` | `AiArtifacts.Deploy`, `AiArtifacts.Use`, `AiHarnesses` | [Get-AiArtifactPlan](Get-AiArtifactPlan.md) |
| `Get-AiArtifactRoster` | `AiArtifacts.Root`, `AiArtifacts.Sources`, `AiArtifacts.Exclude` | [Get-AiArtifactRoster](Get-AiArtifactRoster.md) |
| `Get-AiModRoster` (deprecated) | `AiMods.Root` | [Get-AiModRoster](Get-AiModRoster.md) |
| `Get-AiSkillRoster` (deprecated) | `AiSkills.Root` | [Get-AiSkillRoster](Get-AiSkillRoster.md) |
| `List-AiArtifacts` | `AiArtifacts`, `AiHarnesses`, `ShowFunctionDetailsColors` | [List-AiArtifacts](List-AiArtifacts.md) |
| `Resolve-AiArtifactsConfig` | `AiArtifacts`, `AiHarnesses`, `DefaultWSLUsername`, the deprecated `AiSkills`, `AiMods`, `PathTemplates.SymbolicLinks.AI` and step keys | [Resolve-AiArtifactsConfig](Resolve-AiArtifactsConfig.md) |
| `Resolve-AiModsConfig` (deprecated) | `AiMods`, `DefaultWSLUsername` | [Resolve-AiModsConfig](Resolve-AiModsConfig.md) |
| `Resolve-AiSkillsConfig` (deprecated) | `AiSkills`, `DefaultWSLUsername` | [Resolve-AiSkillsConfig](Resolve-AiSkillsConfig.md) |
| `Update-AiArtifacts` | `AiArtifacts.Sources`, `AiArtifacts.Root` | [Update-AiArtifacts](Update-AiArtifacts.md) |

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them. The deprecated wrappers (marked) forward to their replacement, whose guide covers the configuration.

[Deploy-AiMods](Deploy-AiMods.md) (deprecated), [Deploy-AiSkills](Deploy-AiSkills.md) (deprecated), [Deploy-CoreAiRules](Deploy-CoreAiRules.md) (deprecated), [Get-AiSkillDescription](Get-AiSkillDescription.md), [Get-AiSkillManifest](Get-AiSkillManifest.md), [List-Skills](List-Skills.md) (deprecated), [Resolve-AiModsPluginDirs](Resolve-AiModsPluginDirs.md), [Set-ClaudeSettingsEnv](Set-ClaudeSettingsEnv.md), [Set-ClaudeSettingsKey](Set-ClaudeSettingsKey.md), [Test-AiModsCli](Test-AiModsCli.md), [Update-AiMods](Update-AiMods.md) (deprecated), [Update-AiSkills](Update-AiSkills.md) (deprecated)

## Related

- [AI module reference](../../../modules/ai.md) - what each function does
- [AI Artifacts](../../../ai/artifacts.md) - the design, and migrating from 1.5
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module
