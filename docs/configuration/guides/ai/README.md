# AI Module Configuration Guides

One configuration guide per exported function of the `AI` module, which covers machine-global AI coding agent setup: the CoreAiRules enforcement layer, Agent Skills deployment across Claude Code, Codex CLI and Gemini CLI, and Claude Code mods vendoring and deployment, plus plugin marketplace registration.

The [AI module reference](../../../modules/ai.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

| Function | Configuration keys | Guide |
| -------- | ------------------ | ----- |
| `Deploy-AiMarketplaces` | `AiMarketplaces`, `BootstrapConfig.Steps.AiMarketplaces`, `DefaultWSLDistribution`, `DefaultWSLUsername` | [Deploy-AiMarketplaces](Deploy-AiMarketplaces.md) |
| `Deploy-AiMods` | `AiMods`, `BootstrapConfig.Steps.AiMods`, `DefaultWSLDistribution`, `DefaultWSLUsername` | [Deploy-AiMods](Deploy-AiMods.md) |
| `Deploy-AiSkills` | `AiSkills`, `DefaultWSLDistribution`, `DefaultWSLUsername` | [Deploy-AiSkills](Deploy-AiSkills.md) |
| `Deploy-CoreAiRules` | `DefaultWSLDistribution` | [Deploy-CoreAiRules](Deploy-CoreAiRules.md) |
| `Get-AiModRoster` | `AiMods.Root` | [Get-AiModRoster](Get-AiModRoster.md) |
| `Get-AiSkillRoster` | `AiSkills.Root` | [Get-AiSkillRoster](Get-AiSkillRoster.md) |
| `List-Skills` | `AiSkills`, `ShowFunctionDetailsColors` | [List-Skills](List-Skills.md) |
| `Resolve-AiModsConfig` | `AiMods`, `DefaultWSLUsername` | [Resolve-AiModsConfig](Resolve-AiModsConfig.md) |
| `Resolve-AiSkillsConfig` | `AiSkills`, `DefaultWSLUsername` | [Resolve-AiSkillsConfig](Resolve-AiSkillsConfig.md) |
| `Update-AiMods` | `AiMods` | [Update-AiMods](Update-AiMods.md) |
| `Update-AiSkills` | `AiSkills` | [Update-AiSkills](Update-AiSkills.md) |

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[Get-AiSkillDescription](Get-AiSkillDescription.md), [Get-AiSkillManifest](Get-AiSkillManifest.md), [Resolve-AiModsPluginDirs](Resolve-AiModsPluginDirs.md), [Set-ClaudeSettingsEnv](Set-ClaudeSettingsEnv.md), [Set-ClaudeSettingsKey](Set-ClaudeSettingsKey.md), [Test-AiModsCli](Test-AiModsCli.md)

## Related

- [AI module reference](../../../modules/ai.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module
