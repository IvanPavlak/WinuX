# Deploy-AiMarketplaces

Registers the configured Claude Code plugin marketplaces in `~\.claude\settings.json`, seeds the plugins' options there, and installs the listed plugins through `claude plugin install`, so a marketplace-published plugin reaches every machine from one configuration entry.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiMarketplaces.Marketplaces`](../../configuration-reference.md#ai-marketplaces) | hashtable | empty | The marketplaces to register, keyed by the name Claude Code knows them by. Each entry names the GitHub `Repository` (`owner/name`) and the `Plugins` to install from it. |
| [`AiMarketplaces.PluginConfigs`](../../configuration-reference.md#ai-marketplaces) | hashtable | empty | Plugin options written beneath `pluginConfigs.<plugin>` of the settings file, one child key at a time. |
| [`BootstrapConfig.Steps.AiMarketplaces`](../../configuration-reference.md#bootstrapconfig) | boolean | `$false` | Whether Bootstrap runs this function. OFF by default - the base names no marketplaces. |
| [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL distribution whose `\\wsl.localhost` share carries the WSL settings file. Empty means Windows only. |
| [`DefaultWSLUsername`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL account whose `~/.claude/settings.json` also receives the marketplaces and options. Empty means Windows only. |

The settings file itself is not a configuration key: it is always the user's `~\.claude\settings.json` (and `/home/<DefaultWSLUsername>/.claude/settings.json` in WSL), the file Claude Code reads `extraKnownMarketplaces` and `pluginConfigs` from. Only those keys are written; every other setting is kept.

## Decisions

1. Which marketplaces should every machine know?
    - Options: Any GitHub repository carrying `.claude-plugin/marketplace.json`. The key is the marketplace's name (the `name` in that file), the plugin ids become `<plugin>@<name>`.
    - Default: None - the base ships no marketplaces.
    - More detail: [`AiMarketplaces.Marketplaces`](../../configuration-reference.md#ai-marketplaces)
2. Which plugins should be installed from each?
    - Options: List plugin names under `Plugins`; leave it out to register the marketplace alone and install by hand.
    - Default: None.
    - More detail: [`AiMarketplaces.Marketplaces`](../../configuration-reference.md#ai-marketplaces)
3. Should the repository carry the plugins' options?
    - Options: Put the options under `PluginConfigs.<plugin>` in the shape the plugin documents (a plugin that reads `options`: `options = @{ ... }`); each child key replaces the same key in the settings file and leaves the other children alone. Leave it out to configure through `/plugin` only.
    - Default: None.
    - More detail: [`AiMarketplaces.PluginConfigs`](../../configuration-reference.md#ai-marketplaces)
4. Should Bootstrap register and install on every run?
    - Options: `$true` to register, seed and install (already installed plugins are left alone) on every Bootstrap; `$false` to run `Deploy-AiMarketplaces` by hand.
    - Default: `$false`.
    - More detail: [`BootstrapConfig.Steps`](../../configuration-reference.md#bootstrapconfig)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so a `Plugins` array you supply replaces the base one entirely.

## Steps Overview

1. Name the marketplaces and their plugins under `AiMarketplaces.Marketplaces`
2. Carry the plugins' options under `AiMarketplaces.PluginConfigs` (optional)
3. Enable `BootstrapConfig.Steps.AiMarketplaces`
4. Reload and confirm the merge landed

## Step 1: Name the marketplaces and their plugins

```powershell
AiMarketplaces = @{
    Marketplaces = @{
        "my-marketplace" = @{
            Repository = "MyOrg/MyMarketplace"
            Plugins    = @("my-plugin")
        }
    }
}
```

## Step 2: Carry the plugins' options

The shape beneath the plugin's key is the plugin's own. Each child key (`options` here) replaces that key in the settings file whole; other children survive.

```powershell
AiMarketplaces = @{
    PluginConfigs = @{
        "my-plugin" = @{
            options = @{
                theme = "dark"
                pulse = $true
            }
        }
    }
}
```

## Step 3: Enable `BootstrapConfig.Steps.AiMarketplaces`

With the step on, Bootstrap runs `Deploy-AiMarketplaces` right after `Deploy-AiMods`. Give each plugin one loading path: a plugin loaded from a folder by `Deploy-AiMods` and installed from a marketplace would run twice.

```powershell
BootstrapConfig = @{
    Steps = @{
        AiMarketplaces = $true
    }
}
```

## Step 4: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
Get-ConfigSetting -Path 'AiMarketplaces'
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Resolve-BootstrapSteps | Where-Object Name -eq "AiMarketplaces"
(Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json).extraKnownMarketplaces
(Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json).pluginConfigs
claude plugin list
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLDistribution = "Ubuntu"
    DefaultWSLUsername     = "you"
    AiMarketplaces         = @{
        Marketplaces  = @{
            "my-marketplace" = @{
                Repository = "MyOrg/MyMarketplace"
                Plugins    = @("my-plugin")
            }
        }
        PluginConfigs = @{
            "my-plugin" = @{
                options = @{ theme = "dark" }
            }
        }
    }
    BootstrapConfig        = @{
        Steps = @{
            AiMarketplaces = $true
        }
    }
}
```

## Related

- [`Deploy-AiMarketplaces` in the AI module reference](../../../modules/ai.md#deploy-aimarketplaces) - parameters, usage and behaviour
- [AI Mods](../../../ai/mods.md) - the design, including how marketplaces compare with folder-loaded mods
- [AI configuration guides](README.md) - every guide for this module
- [`Set-ClaudeSettingsKey`](Set-ClaudeSettingsKey.md) - the settings writer this function uses
- [`Deploy-AiMods`](Deploy-AiMods.md) - the folder-loading alternative
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
