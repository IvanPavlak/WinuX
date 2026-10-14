# Clear-WhatsAppLocalStorage

Clears WhatsApp Desktop local storage to resolve startup issues.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal.WhatsAppLocalStoragePath`](../../configuration-reference.md#universal-paths) | string (placeholder path) | `"{User}\AppData\Local\Packages\5319275A.WhatsAppDesktop_cv1g1gvanyjgm\LocalState\shared\transfers"` | The directory whose contents are listed and then deleted (recursively, after confirmation). Expanded by `Load-PathConfiguration`, so `{User}` works here. |

## Decisions

1. Is the shipped WhatsApp storage path the one to clear on this machine?
    - Options: Override `Universal.WhatsAppLocalStoragePath` with an absolute or placeholder path, for example when the Store package folder name differs. Everything under the path is deleted, so point it at the cache directory only.
    - Default: The shipped `transfers` folder of the Microsoft Store WhatsApp Desktop package.
    - More detail: [`Universal`](../../configuration-reference.md#universal-paths)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Universal.WhatsAppLocalStoragePath`
2. Reload and confirm the merge landed

## Step 1: Set `Universal.WhatsAppLocalStoragePath`

Only needed when the shipped path is wrong on this machine. `Universal` is a hashtable, so this one key merges over the base and every other `Universal` key stays as shipped.

```powershell
Universal = @{
    WhatsAppLocalStoragePath = "{User}\AppData\Local\Packages\5319275A.WhatsAppDesktop_cv1g1gvanyjgm\LocalState\shared\transfers"
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.WhatsAppLocalStoragePath
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.WhatsAppLocalStoragePath
Test-Path $global:Configuration.Universal.WhatsAppLocalStoragePath
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal = @{
        WhatsAppLocalStoragePath = "{User}\AppData\Local\Packages\5319275A.WhatsAppDesktop_cv1g1gvanyjgm\LocalState\shared\transfers"
    }
}
```

## Related

- [`Clear-WhatsAppLocalStorage` in the System module reference](../../../modules/system.md#clear-whatsapplocalstorage) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
