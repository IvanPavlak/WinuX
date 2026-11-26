# Resolve-AiPluginConfigs

Resolves the plugin options `Deploy-AiMarketplaces` seeds for one machine type: `AiMarketplaces.PluginConfigs` with the matching `AiMarketplaces.MachinePluginConfigs` rows merged over it.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AiMarketplaces.PluginConfigs`](../../configuration-reference.md#ai-marketplaces) | hashtable | empty | The plugin options every machine type seeds, keyed by plugin name. |
| [`AiMarketplaces.MachinePluginConfigs`](../../configuration-reference.md#ai-marketplaces) | hashtable | empty | The differences per machine type: rows keyed by machine scope (`"PC"`, `"Laptop/Work"`, `"All"`), each shaped like `PluginConfigs` and merged over it on the machine types it covers. |
| [`ValidMachineTypes`](../../configuration-reference.md#valid-machine-types) | array of strings | `@("Test")` | The machine types a row key may name (checked through `Test-MachineTypeScope`); any other token is reported and its row never applies. |

A row is deep-merged: nested hashtables merge key by key, everything else is replaced. The `All` row applies first, then the other matching rows in alphabetical key order. A value a row sets to `$null` is removed, so a machine type can drop an option as well as change it.

## Decisions

1. Should some machine types get other plugin options than the rest?
    - Options: Add a row to `MachinePluginConfigs` keyed by machine scope, holding only what differs; set an option to `$null` to drop it on those machine types. Leave the table empty when every machine draws the same.
    - Default: Empty - every machine type seeds `PluginConfigs` as it is.
    - More detail: [`AiMarketplaces.MachinePluginConfigs`](../../configuration-reference.md#ai-marketplaces)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so an array option a row names replaces the default array entirely.

## Steps Overview

1. Set the options every machine seeds under `AiMarketplaces.PluginConfigs`
2. Add the differences under `AiMarketplaces.MachinePluginConfigs`
3. Reload and confirm the merge landed

## Step 1: Set the options every machine seeds

These are configured on the [`Deploy-AiMarketplaces`](Deploy-AiMarketplaces.md) page.

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

## Step 2: Add the differences per machine type

One row per machine scope. Here the `PC` gets a light theme, and `Laptop` and `Work` drop the `pulse` option; a machine type no row names keeps the options of step 1.

```powershell
AiMarketplaces = @{
    MachinePluginConfigs = @{
        "PC"          = @{
            "my-plugin" = @{ options = @{ theme = "light" } }
        }
        "Laptop/Work" = @{
            "my-plugin" = @{ options = @{ pulse = $null } }
        }
    }
}
```

## Step 3: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
(Resolve-AiPluginConfigs).'my-plugin'.options
```

Run `Deploy-AiMarketplaces` (or Bootstrap with `Steps.AiMarketplaces` on) to write the result to the settings file.

## Verification

Read-only checks. None of these change anything.

```powershell
(Resolve-AiPluginConfigs).'my-plugin'.options
(Resolve-AiPluginConfigs -MachineType Work).'my-plugin'.options
(Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json).pluginConfigs
```

An error naming an unknown machine type means a row key carries a token `ValidMachineTypes` does not list; that row applies nowhere until the key is fixed.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    ValidMachineTypes = @("PC", "Laptop", "Work", "Test")
    AiMarketplaces    = @{
        PluginConfigs        = @{
            "my-plugin" = @{
                options = @{ theme = "dark"; pulse = $true }
            }
        }
        MachinePluginConfigs = @{
            "PC"          = @{
                "my-plugin" = @{ options = @{ theme = "light" } }
            }
            "Laptop/Work" = @{
                "my-plugin" = @{ options = @{ pulse = $null } }
            }
        }
    }
}
```

## Related

- [`Resolve-AiPluginConfigs` in the AI module reference](../../../modules/ai.md#resolve-aipluginconfigs) - parameters, usage and behaviour
- [`Deploy-AiMarketplaces`](Deploy-AiMarketplaces.md) - writes the resolved options to the settings files
- [AI Mods](../../../ai/mods.md) - the design
- [AI configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
