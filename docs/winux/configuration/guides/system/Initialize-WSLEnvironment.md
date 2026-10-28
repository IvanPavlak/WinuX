# Initialize-WSLEnvironment

Initializes the configured WSL distribution with shell tooling.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL distribution every WSL-touching function uses. Ships empty, and that is deliberate: `Configure-WSL`, `Initialize-WSLEnvironment`, `Configure-WSLSSH`, `Open-WSLTab`, `Deploy-AiArtifacts` and WSL symlinks all no-op until it is set. |
| [`Universal.OhMyPoshThemeFile`](../../configuration-reference.md#universal-paths) | string (placeholder path) | `"{User}\AppData\Local\Programs\oh-my-posh\themes\WinuX.omp.json"` | Only its FILE NAME is used: the WSL `~/.profile` line loads `/mnt/c/Users/<Windows user>/AppData/Local/Programs/oh-my-posh/themes/<file name>`, whatever directory the key names. Unset falls back to `WinuX.omp.json`. |

## Decisions

1. Which WSL distribution should WinuX use?
    - Options: A distribution name as `wsl -l -q` prints it, e.g. `Ubuntu`. Leave empty to keep every WSL feature switched off.
    - Default: Empty - every WSL path no-ops.
    - More detail: [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration)
2. Which Oh My Posh theme should the WSL prompt use?
    - Options: The theme `Universal.OhMyPoshThemeFile` names for the Windows prompt. The file must sit in the Windows user's `AppData\Local\Programs\oh-my-posh\themes` folder, because only its name is carried over. The line is written once - a later theme change needs the `oh-my-posh init bash` line in `~/.profile` edited by hand.
    - Default: `WinuX.omp.json`.
    - More detail: [`Universal`](../../configuration-reference.md#universal-paths)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `DefaultWSLDistribution`
2. Set `Universal.OhMyPoshThemeFile` (only if needed)
3. Reload and confirm the merge landed

## Step 1: Set `DefaultWSLDistribution`

The WSL distribution every WSL-touching function uses. Ships empty, and that is deliberate: `Configure-WSL`, `Initialize-WSLEnvironment`, `Configure-WSLSSH`, `Open-WSLTab`, `Deploy-AiArtifacts` and WSL symlinks all no-op until it is set.

```powershell
DefaultWSLDistribution = "Ubuntu"
```

## Step 2: Set `Universal.OhMyPoshThemeFile` (only if needed)

Only the file name reaches WSL, so keep the theme in the Windows Oh My Posh themes folder. `Universal` is a hashtable, so this one key merges over the base and every other `Universal` key stays as shipped.

```powershell
Universal = @{
    OhMyPoshThemeFile = "{User}\AppData\Local\Programs\oh-my-posh\themes\MyTheme.omp.json"
}
```

## Step 3: Reload and confirm the merge landed

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
Split-Path -Leaf $global:Configuration.Universal.OhMyPoshThemeFile
Test-WSLDistributionInstalled
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLDistribution = "Ubuntu"
    Universal = @{
        OhMyPoshThemeFile = "{User}\AppData\Local\Programs\oh-my-posh\themes\MyTheme.omp.json"
    }
}
```

## Related

- [`Initialize-WSLEnvironment` in the System module reference](../../../modules/system.md#initialize-wslenvironment) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Open-WSLTab`](../application/Open-WSLTab.md) - reads the same configuration
- [`Test-WSLDistributionInstalled`](../helper/Test-WSLDistributionInstalled.md) - reads the same configuration
- [`Configure-WSL`](Configure-WSL.md) - reads the same configuration
- [`Configure-WSLSSH`](Configure-WSLSSH.md) - reads the same configuration
- [`Initialize-OhMyPosh`](Initialize-OhMyPosh.md) - reads `Universal.OhMyPoshThemeFile` for the Windows prompt
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
