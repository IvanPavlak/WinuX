# Set-Locale

Sets the system locale (user culture and home location).

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DefaultLocale`](../../configuration-reference.md#locale--language) | string | empty string | The locale `Set-Locale` applies by default. Ships empty, so the function no-ops. |
| [`Locales`](../../configuration-reference.md#locale--language) | hashtable of friendly name to culture name | `@{}` (empty) | The locales `Set-Locale` can apply. |

## Decisions

1. Which locale should be the default?
    - Options: A key from your `Locales` map.
    - Default: Empty - `Set-Locale` no-ops.
    - More detail: [`DefaultLocale`](../../configuration-reference.md#locale--language)
2. Which locales should be available?
    - Options: Friendly name to culture name, e.g. `English = "en-US"`.
    - Default: Empty - `Set-Locale` no-ops.
    - More detail: [`Locales`](../../configuration-reference.md#locale--language)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `DefaultLocale`
2. Set `Locales`
3. Reload and confirm the merge landed

## Step 1: Set `DefaultLocale`

The locale `Set-Locale` applies by default. Ships empty, so the function no-ops.

```powershell
DefaultLocale = "English"
```

## Step 2: Set `Locales`

The locales `Set-Locale` can apply.

```powershell
Locales = @{
    English = "en-US"
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultLocale
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultLocale
$global:Configuration.Locales
Display-SystemLanguageSettings
Get-WinSystemLocale
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultLocale = "English"
    Locales = @{
        English = "en-US"
    }
}
```

## Related

- [`Set-Locale` in the System module reference](../../../modules/system.md#set-locale) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Bootstrap`](../bootstrap/Bootstrap.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
