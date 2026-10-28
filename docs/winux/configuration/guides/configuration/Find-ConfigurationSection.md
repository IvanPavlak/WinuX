# Find-ConfigurationSection

Finds a named section's boundaries in `Configuration.psd1`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

`Find-ConfigurationSection` takes the configuration it works on from its caller rather than reading a fixed key, so there is no key table for it.

This is the text-level primitive the `Add-*` writers use to locate a top-level section inside `Configuration.psd1` without parsing and re-emitting the whole file - which is what lets them preserve comments and formatting. It reads no configuration of its own: the section name comes from the caller.

## Decisions

1. Which configuration value are you feeding `Find-ConfigurationSection`?
    - Options: any key from the [configuration reference](../../configuration-reference.md). The guide for the function that actually consumes the value is the one with the decisions in it - see the [Configuration guides index](README.md).
    - Default: nothing to set. `Find-ConfigurationSection` behaves correctly against an empty base configuration.
    - More detail: [Configuration module reference](../../../modules/configuration.md#find-configurationsection)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Find the key your caller needs
2. Reload and confirm the merge landed

## Step 1: Find the key your caller needs

`Find-ConfigurationSection` has no configuration of its own. Work out which value you are actually trying to change, then open that key's guide from the [Configuration guides index](README.md) or look the key up in the [configuration reference](../../configuration-reference.md).

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Keys.Count
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$lines = Get-Content (Join-Path (Get-RepositoryPath).PowerShell "Configuration.psd1")
Find-ConfigurationSection -Lines $lines -SectionName "BrowserGroups"
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

`Find-ConfigurationSection` needs no configuration, so a minimal local file is enough for it to behave correctly:

```powershell
# Configuration.local.psd1
@{
}
```

## Related

- [`Find-ConfigurationSection` in the Configuration module reference](../../../modules/configuration.md#find-configurationsection) - parameters, usage and behaviour
- [Configuration configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
