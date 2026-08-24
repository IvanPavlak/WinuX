# Resolve-SystemThemeSteps

Resolves which `Set-SystemTheme` follow-up steps should run - the actions taken after the theme registry values are written.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`SystemTheme`](../../configuration-reference.md#set-systemtheme-step-toggles) | hashtable with a `Steps` map | `@{ Steps = <4 toggles> }` | Which steps `Set-SystemTheme` performs when it switches theme (app theme, system theme, wallpaper, lock screen). Resolved by `Resolve-SystemThemeSteps`; each step is a boolean or a per-machine-type hashtable with a `Default`. |

## Decisions

1. Which theme steps should run on this machine?
    - Options: Toggle individual `Steps` entries. Wallpaper and lock-screen steps are the ones people most often switch off on a work machine.
    - Default: The shipped four toggles.
    - More detail: [`SystemTheme`](../../configuration-reference.md#set-systemtheme-step-toggles)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `SystemTheme`
2. Reload and confirm the merge landed

## Step 1: Set `SystemTheme`

Which steps `Set-SystemTheme` performs when it switches theme (app theme, system theme, wallpaper, lock screen). Resolved by `Resolve-SystemThemeSteps`; each step is a boolean or a per-machine-type hashtable with a `Default`.

```powershell
SystemTheme = @{
    Steps = @{
        LockScreen = @{ Test = $false; Default = $true }
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.SystemTheme
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.SystemTheme
Resolve-SystemThemeSteps | Format-Table
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    SystemTheme = @{
        Steps = @{
            LockScreen = @{ Test = $false; Default = $true }
        }
    }
}
```

## Related

- [`Resolve-SystemThemeSteps` in the System module reference](../../../modules/system.md#resolve-systemthemesteps) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
