# SymbolicLinkMaker

Creates symbolic links defined in `SymbolicLinks` under `MachineSpecificPaths` in `Configuration.psd1` for the current machine type.

> [!NOTE]
> A **real** file or directory already sitting at a link path is copied into `<Repo>\Backups\Windows\SymbolicLinks\<entry key>\<timestamp>\` before the link replaces it, so pointing a link at a path you already use (a hand-written PowerShell profile, existing PowerToys FancyZones settings) does not lose the original. That folder is gitignored: easy to find, never committed. An entry whose backup cannot be written is skipped rather than replaced, and an existing symlink is replaced without a backup. See [Backups](../../../reference/backups.md) for the full policy.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PathTemplates.SymbolicLinks`](../../configuration-reference.md#symbolic-links) | nested hashtable of group to link entries | shipped, 2 groups | Every symbolic link `SymbolicLinkMaker` creates: `@{ <Group> = @{ <Name> = @{ Source; Target } } }`, with placeholders on both sides. WSL targets are supported and are what the AI-instruction links use. |
| [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL distribution every WSL-touching function uses. Ships empty, and that is deliberate: `Configure-WSL`, `Initialize-WSLEnvironment`, `Configure-WSLSSH`, `Open-WSLTab`, `Deploy-CoreAiRules` and WSL symlinks all no-op until it is set. |

## Decisions

1. Which symbolic links does this machine need?
    - Options: One entry per link, grouped by the app it belongs to. See [Add Symbolic Link](../system/add-symbolic-link.md) for the full shape and the WSL notes.
    - Default: The shipped groups.
    - More detail: [`PathTemplates.SymbolicLinks`](../../configuration-reference.md#symbolic-links)
2. Which WSL distribution should WinuX use?
    - Options: A distribution name as `wsl -l -q` prints it, e.g. `Ubuntu`. Leave empty to keep every WSL feature switched off.
    - Default: Empty - every WSL path no-ops.
    - More detail: [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `PathTemplates.SymbolicLinks`
2. Set `DefaultWSLDistribution`
3. Reload and confirm the merge landed

## Step 1: Set `PathTemplates.SymbolicLinks`

Every symbolic link `SymbolicLinkMaker` creates: `@{ <Group> = @{ <Name> = @{ Source; Target } } }`, with placeholders on both sides. WSL targets are supported and are what the AI-instruction links use.

```powershell
PathTemplates = @{
    SymbolicLinks = @{
        MyApp = @{
            Config = @{ Source = "{RepoRoot}\MyApp\config.json"; Target = "{AppData}\MyApp\config.json" }
        }
    }
}
```

## Step 2: Set `DefaultWSLDistribution`

The WSL distribution every WSL-touching function uses. Ships empty, and that is deliberate: `Configure-WSL`, `Initialize-WSLEnvironment`, `Configure-WSLSSH`, `Open-WSLTab`, `Deploy-CoreAiRules` and WSL symlinks all no-op until it is set.

```powershell
DefaultWSLDistribution = "Ubuntu"
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.PathTemplates
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.PathTemplates
$global:Configuration.DefaultWSLDistribution
Get-SymbolicLinkEntries
$global:MachineSpecificPaths.SymbolicLinks | ConvertTo-Json -Depth 5
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PathTemplates = @{
        SymbolicLinks = @{
            MyApp = @{
                Config = @{ Source = "{RepoRoot}\MyApp\config.json"; Target = "{AppData}\MyApp\config.json" }
            }
        }
    }
    DefaultWSLDistribution = "Ubuntu"
}
```

## Related

- [`SymbolicLinkMaker` in the System module reference](../../../modules/system.md#symboliclinkmaker) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Add-SymbolicLink`](../configuration/Add-SymbolicLink.md) - reads the same configuration
- [`Get-FancyZoneCoordinates`](../window/Get-FancyZoneCoordinates.md) - reads the same configuration
- [`Open-WSLTab`](../application/Open-WSLTab.md) - reads the same configuration
- [`Test-WSLDistributionInstalled`](../helper/Test-WSLDistributionInstalled.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
