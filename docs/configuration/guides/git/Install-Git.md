# Install-Git

Installs Git via WinGet (if not already available) and configures Git global settings.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`GitConfig`](../../configuration-reference.md#git-configuration) | hashtable, 3 keys | `@{ UserName = ""; UserEmail = ""; WingetPackageId = "Git.Git" }` | The Git identity `Install-Git` writes into the global Git config, and the WinGet package it installs Git from. Ships with an empty identity on purpose - it is personal data. |

## Decisions

1. What Git user name should be configured?
    - Options: Your display name as you want it on commits.
    - Default: Empty - `Install-Git` installs Git but configures no identity.
    - More detail: [`GitConfig`](../../configuration-reference.md#git-configuration)
2. What Git email should be configured?
    - Options: The address you want on commits, e.g. `you@example.com`.
    - Default: Empty.
    - More detail: [`GitConfig`](../../configuration-reference.md#git-configuration)
3. Do you need a different Git package?
    - Options: A WinGet package id.
    - Default: `Git.Git`.
    - More detail: [`GitConfig`](../../configuration-reference.md#git-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `GitConfig`
2. Reload and confirm the merge landed

## Step 1: Set `GitConfig`

The Git identity `Install-Git` writes into the global Git config, and the WinGet package it installs Git from. Ships with an empty identity on purpose - it is personal data.

```powershell
GitConfig = @{
    UserName = "Your Name"
    UserEmail = "you@example.com"
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.GitConfig
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.GitConfig
$global:Configuration.GitConfig
git config --global user.name
git config --global user.email
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    GitConfig = @{
        UserName = "Your Name"
        UserEmail = "you@example.com"
    }
}
```

## Related

- [`Install-Git` in the Git module reference](../../../modules/git.md#install-git) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
- [Add New Repository](add-new-repository.md) - repository groups and what `Update-Repositories` walks
- [`Bootstrap`](../bootstrap/Bootstrap.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
