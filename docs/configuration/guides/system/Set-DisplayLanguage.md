# Set-DisplayLanguage

Sets the Windows display language.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DefaultDisplayLanguage`](../../configuration-reference.md#locale--language) | string | empty string | The Windows display language `Set-DisplayLanguage` applies when called with no argument. Ships empty, so the function no-ops until you set it. |
| [`DisplayLanguages`](../../configuration-reference.md#locale--language) | hashtable of friendly name to language tag | `@{}` (empty) | The display languages `Set-DisplayLanguage` can install and select. |

## Decisions

1. Which Windows display language should be the default?
    - Options: A key from your `DisplayLanguages` map.
    - Default: Empty - `Set-DisplayLanguage` reports that nothing is configured and returns.
    - More detail: [`DefaultDisplayLanguage`](../../configuration-reference.md#locale--language)
2. Which display languages should be available?
    - Options: Friendly name to Windows language tag, e.g. `English = "en-US"`.
    - Default: Empty - `Set-DisplayLanguage` has nothing to choose from.
    - More detail: [`DisplayLanguages`](../../configuration-reference.md#locale--language)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `DefaultDisplayLanguage`
2. Set `DisplayLanguages`
3. Reload and confirm the merge landed

## Step 1: Set `DefaultDisplayLanguage`

The Windows display language `Set-DisplayLanguage` applies when called with no argument. Ships empty, so the function no-ops until you set it.

```powershell
DefaultDisplayLanguage = "English"
```

## Step 2: Set `DisplayLanguages`

The display languages `Set-DisplayLanguage` can install and select.

```powershell
DisplayLanguages = @{
    English = "en-US"
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultDisplayLanguage
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultDisplayLanguage
$global:Configuration.DisplayLanguages
Display-SystemLanguageSettings
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultDisplayLanguage = "English"
    DisplayLanguages = @{
        English = "en-US"
    }
}
```

## Related

- [`Set-DisplayLanguage` in the System module reference](../../../modules/system.md#set-displaylanguage) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Bootstrap`](../bootstrap/Bootstrap.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
