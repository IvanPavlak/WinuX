# Test-WSLDistributionInstalled

Tests whether the configured WSL distribution (the `DefaultWSLDistribution` key in `Configuration.psd1`) is installed on the system.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL distribution every WSL-touching function uses. Ships empty, and that is deliberate: `Configure-WSL`, `Initialize-WSLEnvironment`, `Configure-WSLSSH`, `Open-WSLTab`, `Deploy-CoreAiRules` and WSL symlinks all no-op until it is set. |

## Decisions

1. Which WSL distribution should WinuX use?
    - Options: A distribution name as `wsl -l -q` prints it, e.g. `Ubuntu`. Leave empty to keep every WSL feature switched off.
    - Default: Empty - every WSL path no-ops.
    - More detail: [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `DefaultWSLDistribution`
2. Reload and confirm the merge landed

## Step 1: Set `DefaultWSLDistribution`

The WSL distribution every WSL-touching function uses. Ships empty, and that is deliberate: `Configure-WSL`, `Initialize-WSLEnvironment`, `Configure-WSLSSH`, `Open-WSLTab`, `Deploy-CoreAiRules` and WSL symlinks all no-op until it is set.

```powershell
DefaultWSLDistribution = "Ubuntu"
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultWSLDistribution
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultWSLDistribution
Test-WSLDistributionInstalled
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLDistribution = "Ubuntu"
}
```

## Related

- [`Test-WSLDistributionInstalled` in the Helper module reference](../../../modules/helper.md#test-wsldistributioninstalled) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [`Open-WSLTab`](../application/Open-WSLTab.md) - reads the same configuration
- [`Configure-WSL`](../system/Configure-WSL.md) - reads the same configuration
- [`Configure-WSLSSH`](../system/Configure-WSLSSH.md) - reads the same configuration
- [`Deploy-CoreAiRules`](../system/Deploy-CoreAiRules.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
